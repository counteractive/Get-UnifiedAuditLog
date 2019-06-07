$RESULT_SIZE_LIMIT = 5000   # max permitted ResultSize parameter
$SESSION_SIZE_LIMIT = 50000 # max permitted under SessionCommand ReturnLargeSet
$DEFAULT_INTERVAL_MINUTES = 30
$DEFAULT_RESULT_SIZE = $RESULT_SIZE_LIMIT
$DEFAULT_SESSION_SIZE = $SESSION_SIZE_LIMIT
$DEFAULT_RETRY_LIMIT = 3

function Get-UnifiedAuditLog {
<#
.SYNOPSIS
Gets event from the Office 365 unified audit log and outputs them into the pipeline (as hashtables).

.DESCRIPTION
The Get-UnifiedAuditLog cmdlet is a wrapper around the Search-UnifiedAuditLog cmdlet that allows you to get data from the unified auditing log available in the Office 365 Security & Compliance Center. For more information, see Search the audit log in the Office 365 Security & Compliance Center (https://go.microsoft.com/fwlink/p/?LinkId=708432).  It is renamed because it does not support "search" parameters outside of the start and end dates, it is designed for bulk data gathering.

The cmdlet needs to be run with the Exchange powershell module (see https://docs.microsoft.com/en-us/powershell/exchange/exchange-online/connect-to-exchange-online-powershell/mfa-connect-to-exchange-online-powershell?view=exchange-ps) which provides the wrapped cmdlets Search-UnifiedAuditLog and Connect-EXOPSSession.

If your goal is simply to retrieve the audit logs in a usable format, the Search-UnifiedAuditLog cmdlet is very difficult to use.  This is an effort to smooth out those rough edges, inspired by the script by Tehnoon Raza at https://blogs.msdn.microsoft.com/tehnoonr/2018/01/26/retrieving-office-365-audit-data-using-powershell/, posted January 26, 2018.

Microsoft recommends "if you want to programmatically download data from the Office 365 audit log ... use the Office 365 Management Activity API".  What they don't say is that using the Management API involves creating an Azure app, managing client keys, and after all that can only access the past 7 days of records.  The Office 365 Management Activity API is certainly useful, but is more cumbersome to use.  See its documentation at https://go.microsoft.com/fwlink/p/?linkid=852309.

As with Search-UnifiedAuditLog, you need to be assigned permissions before you can run this cmdlet. To find the permissions required to run any cmdlet or parameter in your organization, see Find the permissions required to run any Exchange cmdlet (https://technet.microsoft.com/library/mt432940.aspx), and look for Search-UnifiedAuditLog.

.EXAMPLE
PS C:\> Get-UnifiedAuditLog -StartDate (Get-Date).AddDays(-7) -Upn user@o365.domain.com -IntervalMinutes 120 -Verbose -WarningAction 'Continue' | ConvertTo-Json -Compress -Depth 100 | Out-File .\o365.logs.json -Encoding UTF8

Retrieve the past week's worth of logs using an interval window of 240 minutes.  The interval should be the max available that keeps each "batch" of results under the limit (typically 50,000).  Just FYI, pipe to Out-File and specify the encoding if you plan to use the JSON with any other tooling (jq, filebeat), otherwise you'll get UTF-16 by default (e.g., with the redirect operator (>)).

.PARAMETER StartDate
The StartDate parameter specifies the start date of the date range.

Use the short date format that's defined in the Regional Options settings on the computer where you're running the command. For example, if the computer is configured to use the short date format mm/dd/yyyy, enter 09/01/2018 to specify September 1, 2018. You can enter the date only, or you can enter the date and time of day. If you enter the date and time of day, enclose the value in quotation marks ("), for example, "09/01/2018 5:00 PM".

If you don't include a timestamp in the value for this parameter, the default timestamp is 12:00 AM (midnight) on the specified date.

If omitted, the default for StartDate is the 90 days before the current date, as returned by Get-Date, which corresponds roughly to the oldest logs available.

.PARAMETER EndDate
The EndDate parameter specifies the end date of the date range.

Use the short date format that's defined in the Regional Options settings on the computer where you're running the command. For example, if the computer is configured to use the short date format mm/dd/yyyy, enter 09/01/2018 to specify September 1, 2018. You can enter the date only, or you can enter the date and time of day. If you enter the date and time of day, enclose the value in quotation marks ("), for example, "09/01/2018 5:00 PM".

If you don't include a timestamp in the value for this parameter, the default timestamp is 12:00 AM (midnight) on the specified date.

If omitted, the default for EndDate is the current date, as returned by Get-Date

.PARAMETER IntervalMinutes
The IntervalMinutes parameter specifies the size of the window (in minutes) into which the cmdlet will break the overall timespan.  Smaller intervals lead to more requests, but the underlying cmdlet cannot return more than 50,000 records for a single session ID, so bigger is not always better.  Plus, if you keep this modest, you get more granular progress monitoring.

In the future one could put some logic in this cmdlet to optimize this automatically, but for now it's by hand.  The default is 30 minutes, which usually works fine.

.PARAMETER ResultSize
The ResultSize parameter specifies the maximum number of results to return. The default value is 100, maximum is 5,000.  This is usually fine at the default, and may be removed in future versions.

.NOTES
Submit issues, contribute, and view the license at https://github.com/counteractive.
#>

  [CmdletBinding()]

  Param (
    [DateTime] $StartDate,
    [DateTime] $EndDate,
    [Int32] $IntervalMinutes,
    [Int32] $ResultSize,
    [Int32] $SessionSize,
    [Int32] $RetryLimit,
    [Parameter(Mandatory=$true)] [String] $Upn
  )

  # parameter defaults and invariants:
  $TODAY = (Get-Date)
  $OLDEST = $TODAY.AddDays(-90)

  if (!$StartDate) { $StartDate = $OLDEST }
  if ( $StartDate -lt $OLDEST ){
    Write-Verbose "StartDate can be no earlier than 90 days ago.  Resetting StartDate to $OLDEST"
    $StartDate = $OLDEST
  }
  if (!$EndDate) { $EndDate = $TODAY }
  if ($EndDate -gt $TODAY){
    Write-Verbose "EndDate can be no newer than today.  Resetting EndDate to $TODAY"
    $EndDate = $TODAY
  }
  if (!$IntervalMinutes) { $IntervalMinutes = $DEFAULT_INTERVAL_MINUTES }
  if (!$ResultSize) { $ResultSize = $DEFAULT_RESULT_SIZE }
  if (!$SessionSize) { $SessionSize = $DEFAULT_SESSION_SIZE }
  if (!$RetryLimit){ $RetryLimit = $DEFAULT_RETRY_LIMIT }

  Connect-EXOPSSession -UserPrincipalName $upn
  $intervalStart = $StartDate
  $totalRecords = 0

  Write-Verbose "Retrieving audit logs between $StartDate and $EndDate"
  $span = ($EndDate - $StartDate).TotalMinutes
  $intervalCount = [math]::Ceiling($span/$IntervalMinutes)
  $currentInterval = 0
  $progress = 0
  $errorCount = 0
  Write-Progress -Activity "Retrieving audit logs" -Status "$progress% Complete:" -PercentComplete $progress


  while ($intervalStart -lt $EndDate){

    $intervalEnd = $intervalStart.AddMinutes($intervalMinutes)
    if ($intervalEnd -gt $EndDate) {
      $intervalEnd = $EndDate
    }

    Write-Verbose "  Retrieving audit logs in interval $intervalStart to $intervalEnd"
    $currentInterval = $currentInterval + 1
    $progress = [math]::Round(($currentInterval/$intervalCount) * 100, 2)
    Write-Progress -Activity "Retrieving audit logs" -Status "$progress% Complete:" -PercentComplete $progress

    $retries = 0
    $sessionId = (Get-Date -Format "o") # use ISO 8601 timestamp as session id
    $intervalResultCount = 0  # total results in interval
    $sessionResultCount = -1  # count of session results so far (start -1 for loop condition)

    # loop calls to Search-UnifiedAuditLog within one session (one sessionId)
    while ($retries -lt $RetryLimit -and $sessionResultCount -lt  $intervalResultCount){

      # include -Formatted to "cause attributes that are normally returned as integers (for example, RecordType and Operation) to be formatted as descriptive strings."  This removes the need to add in string versions from the wrapper object:
      $results = Search-UnifiedAuditLog -StartDate $intervalStart -EndDate $intervalEnd -SessionId $sessionId -SessionCommand ReturnLargeSet -ResultSize $ResultSize -Formatted

      if ( !$results -or $results.Count -eq 0) {
          $retries = $retries + 1
          Write-Verbose "    No results, retrying ($retries of $RetryLimit)"
          continue
      }

      $intervalResultCount = $results[0].ResultCount
      $sessionResultCount = [math]::Max($sessionResultCount, 0)

      if ($intervalResultCount -gt $SESSION_SIZE_LIMIT) {
        Write-Warning "    $intervalResultCount records in interval which exceeds session size limit of $SESSION_SIZE_LIMIT. Reduce IntervalMinutes parameter."
        $intervalResultCount = $SESSION_SIZE_LIMIT
      }

      $sessionResultCount = $sessionResultCount + $results.Count
      Write-Verbose "    Retrieved $([math]::Max($sessionResultCount, 0)) of $intervalResultCount interval records"

      # The actual interesting stuff is in the event's AuditData field, which is a JSON string (!) that needs decoding.  The wrapper object has a RecordType string that is useful to add back in.  Unfortunately, it's also common that JSON string is unterminated, so you also have to catch that error.  Like so:

      foreach ($event in $results){
        try{
          # $h = @{}
          # $o = ($event.AuditData | ConvertFrom-Json)
          # foreach( $p in $o.PSObject.Properties.Name ){ $h[$p] = $o.$p }
          # $h['RecordTypeString'] = $event.RecordType
          Write-Output ($event.AuditData | ConvertFrom-Json)
        } catch {
          $errorCount = $errorCount + 1
          Write-Warning "    Error converting from JSON, probably unterminated string, skipping record ($errorCount records skipped)"
        }
      }
    }

    Write-Verbose "  Retrieved $([math]::Max($sessionResultCount, 0)) total interval records (session id $sessionId)"
    $totalRecords = $totalRecords + $sessionResultCount
    $intervalStart = $intervalEnd

  }
  Write-Verbose "Retrieved $totalRecords total records from $StartDate to $EndDate"
  Get-PSSession | Remove-PSSession
}

Export-ModuleMember -Function Get-UnifiedAuditLog