function Set-DbaFileStream {
    <#
        .SYNOPSIS
            Sets the status of FileStream on specified SQL Server instances

        .DESCRIPTION
            Connects to the specified SQL Server instances, and sets the status of the FileStream feature to the required value

            To perform the action, the SQL Server instance must be restarted. By default we will prompt for confirmation for this action, this can be overridden with the -Force switch

        .PARAMETER SqlInstance
            The SQL Server instance to connect to.

        .PARAMETER SqlCredential
            Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted). To use:

            $scred = Get-Credential, then pass $scred object to the -SqlCredential parameter.

            Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.

            To connect as a different Windows user, run PowerShell as that user.

        .PARAMETER FileStreamLevel
            The level to of FileStream to be enabled:
            0 - FileStream disabled
            1 - T-Sql Access Only
            2 - T-Sql and Win32 access enabled
            3 - T-Sql, Win32 and Remote access enabled

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .PARAMETER WhatIf
            If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

        .PARAMETER Confirm
            If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

        .NOTES
            Tags: Filestream
            Author: Stuart Moore ( @napalmgram )

            dbatools PowerShell module (https://dbatools.io)
            Copyright (C) 2016 Chrissy LeMaire
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

        .EXAMPLE
            Set-DbaFileStream -SqlInstance server1\instance2 -FileStreamLevel T-Sql Only
            Set-DbaFileStream -SqlInstance server1\instance2 -FileStreamLevel 1

            These commands are functionally equivalent, both will set Filestream level on server1\instance2 to T-Sql Only

        .EXAMPLE
            Get-DbaFileStream -SqlInstance server1\instance2, server5\instance5 , prod\hr | Where-Object {$_.FileSteamStateID -gt 0} | Set-DbaFileStream -FileStreamLevel 0 -Force

            Using this pipeline you can scan a range of SQL instances and disable filestream on only those on which it's enabled
        #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "High")]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ParameterSetName='piped')]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstance[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [ValidateSet("Disabled", "Transact-SQL-Enabled", "Full-Access-Enabled")]
        [object]$FileStreamLevel,
        [switch]$Force,
        [Alias('Silent')]
        [switch]$EnableException
    )
    begin {
		$idServiceFS =[ordered]@{
			0 = 'Disabled'
			1 = 'Transact-SQL access'
			2 = 'Transact-SQL and I/O access'
			3 = 'Transact-SQL, I/O and remote client access'
		}
		$idInstanceFS =[ordered]@{
			0 = 'Disabled'
			1 = 'Transact-SQL access enabled'
			2 = 'Full access enabled'
		}

        if ($FileStreamLevel -notin ('0', '1', '2')) {
            $NewFileStream = switch ($FileStreamLevel) {
                "Disabled" {0}
                "T-Sql Only" {1}
                "T-Sql and Win-32 Access" {2}
            }
        }
        else {
            $NewFileStream = $FileStreamLevel
        }
    }
    process {
        foreach ($instance in $SqlInstance) {
            $computer = $instance.ComputerName
            $instanceName = $instance.InstanceName

            <# Get Service-Level information #>
            if ($instance.IsLocalHost) {
                $computerName = $computer
            }
            else {
                $computerName = (Resolve-DbaNetworkName -ComputerName $computer -Credential $Credential).FullComputerName
            }

            Write-Message -Level Verbose -Message "Attempting to connect to $computer"
            try {
                $namespace = Get-DbaCmObject -ComputerName $computerName -Namespace root\Microsoft\SQLServer -Query "SELECT NAME FROM __NAMESPACE WHERE NAME LIKE 'ComputerManagement%'" | Where-Object { (Get-DbaCmObject -ComputerName $computerName -Namespace $("root\Microsoft\SQLServer\" + $_.Name) -ClassName FilestreamSettings).Count -gt 0} | Sort-Object Name -Descending | Select-Object -First 1

                if ($namespace.Name) {
                    $serviceFS = Get-DbaCmObject -ComputerName $computerName -Namespace $("root\Microsoft\SQLServer\" + $namespace.Name) -ClassName FilestreamSettings | Where-Object InstanceName -eq $instanceName | Select-Object -First 1
                }
                else {
                    Write-Message -Level Warning -Message "No ComputerManagement was found on $computer. Service level information may not be collected." -Target $computer
                }
            }
            catch {
                Stop-Function -Message "Issue collecting service-level information on $computer for $instanceName" -Target $computer -ErrorRecord $_ -Exception $_.Exception -Continue
            }

            <# Get Instance-Level information #>
            try {
                Write-Message -Level Verbose -Message "Connecting to $instance."
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential -MinimumVersion 10
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

			try {
				$instanceFS = Get-DbaSpConfigure -SqlInstance $server -ConfigName FilestreamAccessLevel | Select-Object ConfiguredValue, RunningValue
			}
			catch {
				Stop-Function -Message "Issue collectin instance-level configuration on $instanceName" -Target $server -ErrorRecord $_ -Exception $_.Exception -Continue
			}

            if ($FileStreamState -ne $NewFileStream) {
                if ($force -or $PSCmdlet.ShouldProcess($instance, "Changing from `"$($OutputLookup[$FileStreamState])`" to `"$($OutputLookup[$NewFileStream])`"")) {
                    $server.Configuration.FilestreamAccessLevel.ConfigValue = $NewFileStream
                    $server.alter()
                }

                if ($force -or $PSCmdlet.ShouldProcess($instance, "Need to restart Sql Service for change to take effect, continue?")) {
                    $RestartOutput = Restart-DbaSqlService -ComputerName $server.ComputerNamePhysicalNetBIOS -InstanceName $server.InstanceName -Type Engine
                }
            }
            else {
                Write-Message -Level Verbose -Message "Skipping restart as old and new FileStream values are the same"
                $RestartOutput = [PSCustomObject]@{Status = 'No restart, as no change in values'}
            }
            [PsCustomObject]@{
                SqlInstance   = $server
                OriginalValue = $OutputLookup[$FileStreamState]
                NewValue      = $OutputLookup[$NewFileStream]
                RestartStatus = $RestartOutput.Status
            }

        }
    }
    END {}
}