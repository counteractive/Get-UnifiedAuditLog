# Get-UnifiedAuditLog

## Synopsis

Gets event from the Office 365 unified audit log and outputs them into the pipeline.

## Description

The Get-UnifiedAuditLog cmdlet is a wrapper around the Search-UnifiedAuditLog cmdlet that allows you to get data from the unified auditing log available in the Office 365 Security & Compliance Center. For more information, see Search the audit log in the [Office 365 Security & Compliance Center](https://go.microsoft.com/fwlink/p/?LinkId=708432).  It is renamed because it does not support "search" parameters outside of the start and end dates, it is designed for bulk data gathering.

The cmdlet needs to be run with the [Exchange powershell module](https://docs.microsoft.com/en-us/powershell/exchange/exchange-online/connect-to-exchange-online-powershell/mfa-connect-to-exchange-online-powershell?view=exchange-ps) which provides the wrapped cmdlets Search-UnifiedAuditLog and Connect-EXOPSSession.

If your goal is simply to retrieve the audit logs in a usable format, the Search-UnifiedAuditLog cmdlet is very difficult to use.  This is an effort to smooth out those rough edges, inspired by [a script by Tehnoon Raza](https://blogs.msdn.microsoft.com/tehnoonr/2018/01/26/retrieving-office-365-audit-data-using-powershell/) posted January 26, 2018.

Microsoft recommends "if you want to programmatically download data from the Office 365 audit log ... use the Office 365 Management Activity API".  What they don't say is that using the Management API involves creating an Azure app in the portal, managing client keys, and after all that the API can only access the past 7 days of records.  The Office 365 Management Activity API is certainly useful, but is more cumbersome to use.  See its [documentation](https://go.microsoft.com/fwlink/p/?linkid=852309) for more information.

As with Search-UnifiedAuditLog, you need to be assigned permissions before you can run this cmdlet. To find the permissions required to run any cmdlet or parameter in your organization, see [the online docs](https://technet.microsoft.com/library/mt432940.aspx), and look for Search-UnifiedAuditLog.

## Usage and Examples

```powershell
PS C:\> Import-Module .\path\to\Get-UnifiedAuditLog.psm1
```

Import the module to get access to the `Get-UnifiedAuditLog` cmdlet

```powershell
PS C:\> Get-UnifiedAuditLog -StartDate (Get-Date).AddDays(-7) -Upn user@o365.domain.com -IntervalMinutes 120 -Verbose -WarningAction 'Continue' | ConvertTo-Json -Compress -Depth 100 | Out-File .\o365.logs.json -Encoding UTF8
```

Retrieves the past week's worth of logs using an interval window of 240 minutes.  The interval should be the max available that keeps each "batch" of results under the limit (typically 50,000).  Just FYI, pipe to Out-File and specify the encoding if you plan to use the JSON with any other tooling (jq, filebeat), otherwise you'll get UTF-16 by default (e.g., with the redirect operator (>)).

## Parameters

### StartDate

The StartDate parameter specifies the start date of the date range.

Use the short date format that's defined in the Regional Options settings on the computer where you're running the command. For example, if the computer is configured to use the short date format mm/dd/yyyy, enter 09/01/2018 to specify September 1, 2018. You can enter the date only, or you can enter the date and time of day. If you enter the date and time of day, enclose the value in quotation marks ("), for example, "09/01/2018 5:00 PM".

If you don't include a timestamp in the value for this parameter, the default timestamp is 12:00 AM (midnight) on the specified date.

If omitted, the default for StartDate is the 90 days before the current date, as returned by Get-Date, which corresponds roughly to the oldest logs available.

### EndDate

The EndDate parameter specifies the end date of the date range.

Use the short date format that's defined in the Regional Options settings on the computer where you're running the command. For example, if the computer is configured to use the short date format mm/dd/yyyy, enter 09/01/2018 to specify September 1, 2018. You can enter the date only, or you can enter the date and time of day. If you enter the date and time of day, enclose the value in quotation marks ("), for example, "09/01/2018 5:00 PM".

If you don't include a timestamp in the value for this parameter, the default timestamp is 12:00 AM (midnight) on the specified date.

If omitted, the default for EndDate is the current date, as returned by Get-Date

### IntervalMinutes

The IntervalMinutes parameter specifies the size of the window (in minutes) into which the cmdlet will break the overall timespan.  Smaller intervals lead to more requests, but the underlying cmdlet cannot return more than 50,000 records for a single session ID, so bigger is not always better.  Plus, if you keep this modest, you get more granular progress monitoring.

In the future one could put some logic in this cmdlet to optimize this automatically, but for now it's by hand.  The default is 30 minutes, which usually works fine.

### ResultSize

The ResultSize parameter specifies the maximum number of results to return. The default value is 100, maximum is 5,000.  This is usually fine at the default, and may be removed in future versions.

## Notes

Submit issues, contribute, and view the license at the [github repo](https://github.com/counteractive).

## License and Notice

See the included [`LICENSE`](./LICENSE) file for license terms and [NOTICE](./NOTICE) file for attribution.
