function Clear-DbaSuspectPage {
	<#
		.SYNOPSIS
		Clears data that is stored in SQL for Suspect Pages on the specied SQL Server Instance

		.DESCRIPTION
		This function clears records that were stored due to suspect pages in databases on a SQL Server Instance.

		.PARAMETER SqlInstance
		A SQL Server instance to connect to

		.PARAMETER SqlCredential
		A credential to use to conect to the SQL Instance rather than using Windows Authentication

		.PARAMETER Database
        The database to return. If unspecified, all records will be returned.
        
        .PARAMETER Force
        This will clear all records in the suspect pages table.

        .PARAMETER PageId
        Use this parameter in conjunction with Database and FileId to clear only records that match

        .PARAMETER FileId
        Use this parameter in conjunction with Database and PageId to clear only records that match

		.PARAMETER EnableException
		By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
		This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
		Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
		
		.NOTES
		Tags: Pages, DBCC
		Author: Garry Bargsley (@gbargsley), http://blog.garrybargsley.com

		Website: https://dbatools.io
		Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
		License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

		.EXAMPLE
		Clear-DbaSuspectPage -SqlInstance sql2016 -Force

		Removes all records stored for Suspect Pages on the sql2016 SQL Server.
		
		.EXAMPLE
		Clear-DbaSuspectPage -SqlInstance sql2016 -Database Test -PageId 3 -FileId 1

		Clears any records stored for Suspect Pages on the sql2016 SQL Server in the Test database with a PageId of 3 and FileId of 1.

#>
	[CmdletBinding()]
	Param (
		[parameter(Position = 0, Mandatory, ValueFromPipeline)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]$SqlInstance,
		[object]$Database,
       	[PSCredential]$SqlCredential,
        [switch][Alias('Silent')]$EnableException,
        [int]$PageId,
        [int]$FileId,
        [switch]$Force
	)
	
	process {
		
		foreach ($instance in $sqlinstance) {
			try {
				$server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
			}
			catch {
				Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
				return
			}
			
			$sql = "Select
					DB_NAME(database_id) as DBName, 
					file_id, 
					page_id, 
					CASE event_type 
					WHEN 1 THEN '823 or 824 or Torn Page'
					WHEN 2 THEN 'Bad Checksum'
					WHEN 3 THEN 'Torn Page'
					WHEN 4 THEN 'Restored'
					WHEN 5 THEN 'Repaired (DBCC)'
					WHEN 7 THEN 'Deallocated (DBCC)'
					END as EventType, 
					error_count, 
					last_update_date
					from msdb.dbo.suspect_pages"
				
			try {
				$results = $server.Query($sql) 
			}
			catch {
				Stop-Function -Message "Issue collecting data on $server" -Target $server -ErrorRecord $_ -Continue
			}
			
			if ($Database) {
				$results = $results | Where-Object DBName -EQ $Database
			}

		}
		foreach ($row in $results) {
			[PSCustomObject]@{
			  ComputerName   = $server.NetName
			  InstanceName   = $server.ServiceName
			  SqlInstance    = $server.DomainInstanceName
			  Database       = $row.DBName
			  FileId         = $row.file_id
			  PageId         = $row.page_id
			  EventType      = $row.EventType
			  ErrorCount     = $row.error_count
			  LastUpdateDate = $row.last_update_date
			}
		}   
    }
}
