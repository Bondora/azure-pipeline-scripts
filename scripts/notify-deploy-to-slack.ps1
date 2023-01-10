Param(
    [Parameter(Mandatory=$true, HelpMessage="Allowed values 'started' and 'finished'")]
    [ValidateSet("started", "finished")]
    [String] $DeployState,

    [Parameter(Mandatory=$true, HelpMessage="Service's name for Slack message")]
    [String] $ServiceName,

    [Parameter(Mandatory=$true, HelpMessage="Slack API Uri")]
    [String] $SlackApiUri,

    [Parameter(Mandatory=$true, HelpMessage="Slack Auth Token")]
    [String] $SlackAuthToken,

    [Parameter(Mandatory=$true, HelpMessage="Main Slack channel ID to post message")]
    [String] $ChannelId,

    [Parameter(Mandatory=$true, HelpMessage="System Access Token used to call Azure REST API")]
    [String] $SystemAccessToken,

    [Parameter(Mandatory=$false, HelpMessage="Additional Slack channel ID to post message")]
    [String] $AdditionalChannelId,

    [Parameter(Mandatory=$false, HelpMessage="Additional info text to add into Slack message")]
    [String] $InfoMessage = "",

    [Parameter(Mandatory=$false, HelpMessage="If empty then current Stage name is used. Used to find related approvalMessage.")]
    [String] $DeployStageName,

    [Parameter(Mandatory=$false, HelpMessage="Mandatory when DeployState=finished. Format 'Deploy_Stage.Deploy_Job(.Deploy)'")]
    [String] $DeployJobIdentifier,

    [Parameter(Mandatory=$false, HelpMessage="When deploy finished then this is used to post message as respinse to deploy started message")]
    [String] $DeployStartedSlackMessageId,

    [Parameter(Mandatory=$false, HelpMessage="If to show additional information for debugging purposes")]
    [bool] $ShowDebugInfo = $false
)

$deployResult = ""
$color = "good"
$fields = @() # Empty array, add fields later
$pipelineStartedBy = ""
$title = "Deploy $DeployState"

$contentTypeJson = "application/json; charset=utf-8"
$azureAuthHeaders = @{authorization = "Bearer $SystemAccessToken"}

$buildId = $env:BUILD_BUILDID
$buildNumber = $env:BUILD_BUILDNUMBER
$buildReason = $env:BUILD_REASON # Manual, IndividualCI, BatchedCI, Schedule, PullRequest
$projectUri = $env:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI + $env:SYSTEM_TEAMPROJECT

if (!$DeployStageName)
{
    $DeployStageName = $env:SYSTEM_STAGENAME
}

if ($ShowDebugInfo -eq $true)
{
    Write-Output "Input parameters:"
    Write-Output "DeployState: $DeployState"
    Write-Output "ServiceName: $ServiceName"
    Write-Output "SlackApiUri: $SlackApiUri"
    Write-Output "SlackAuthToken: $SlackAuthToken"
    Write-Output "ChannelId: $ChannelId"
    Write-Output "SystemAccessToken: $SystemAccessToken"
    Write-Output "AdditionalChannelId: $AdditionalChannelId"
    Write-Output "InfoMessage: $InfoMessage"
    Write-Output "DeployStageName: $DeployStageName"
    Write-Output "DeployJobIdentifier: $DeployJobIdentifier"
    Write-Output "DeployStartedSlackMessageId: $DeployStartedSlackMessageId"
    Write-Output ""
    Write-Output "Build variables:"
    Write-Output "buildId: $buildId"
    Write-Output "buildNumber: $buildNumber"
    Write-Output "buildReason: $buildReason"
    Write-Output "projectUri: $projectUri"
}

if ($buildReason -eq "Manual")
{
    $pipelineStartedBy = "Pipeline started manually by $env:BUILD_QUEUEDBY"
}
else
{
    $pipelineStartedBy = "Pipeline started automatically for $env:BUILD_REQUESTEDFOR"
}

if ($DeployState -eq "started")
{
    # Get approvalMessage details, first get timeline information for pipelines, then find approvalMessage
    $url = "$projectUri/_apis/build/builds/$buildId/timeline?api-version=7.0"

    if ($ShowDebugInfo -eq $true)
    {
        Write-Output "Get build timeline API result:"
        Write-Output "API Uri: $url"
    }

    # Get timeline aka stages, jobs and tasks for the build
    $result = Invoke-RestMethod -Uri $url -Headers $azureAuthHeaders -ContentType $contentTypeJson -Method Get
    
    if ($ShowDebugInfo -eq $true)
    {
        Write-Output "API result:"
        Write-Output $result | ConvertTo-Json
    }

    # 1. Find the deploy Stage
    if ($result)
    {
        $deployStage = $result.records | Where-Object {($_.identifier -eq $DeployStageName) -and ($_.type -eq "Stage")}

        if ($ShowDebugInfo -eq $true)
        {
            Write-Output "Deploy Stage:"
            Write-Output $deployStage | ConvertTo-Json
        }
    }

    # 2. Find Checkpoint that is related for the deploy Stage
    if ($deployStage -and $deployStage.id)
    {
        $checkpoint = $result.records | Where-Object {($_.parentId -eq $deployStage.id) -and ($_.type -eq "Checkpoint") -and ($_.state -eq "completed")}
        
        if ($ShowDebugInfo -eq $true)
        {
            Write-Output "Checkpoint:"
            Write-Output $checkpoint | ConvertTo-Json
        }
    }

    # 3. Find Approval that is related to the deploy Stage's Checkpoint
    if ($checkpoint -and $checkpoint.id)
    {
        $approval = $result.records | Where-Object {($_.parentId -eq $checkpoint.id) -and ($_.type -eq "Checkpoint.Approval") -and ($_.state -eq "completed")}
        
        if ($ShowDebugInfo -eq $true)
        {
            Write-Output "Checkpoint.Approval:"
            Write-Output $approval | ConvertTo-Json
        }
        $approvalId = $approval.id
    }

    if ($approvalId)
    {
        $url = "$projectUri/_apis/pipelines/approvals/$approvalId`?`$expand=steps&api-version=7.0-preview.1"

        if ($ShowDebugInfo -eq $true)
        {
            Write-Output "Get pipeline approval API result:"
            Write-Output "API Uri: $url"
        }

        $result = Invoke-RestMethod -Uri $url -Headers $azureAuthHeaders -ContentType $contentTypeJson -Method Get

        if ($ShowDebugInfo -eq $true)
        {
            Write-Output "API result:"
            Write-Output $result | ConvertTo-Json
        }

        foreach ($step in $result.steps)
        {
            $approverName = $step.actualApprover.displayName
            $approverUniqueName = $step.actualApprover.uniqueName
            $approvalStatus = $step.status
            $approvalComment = $step.comment
            $approvedOn = $step.lastModifiedOn
            $approvalInitiatedOn = $step.initiatedOn

            if ($approvedOn)
            {
                $approvedOn = $approvedOn.ToString("yyyy-MM-dd HH:mm:ss")
            }
            if ($approvalInitiatedOn)
            {
                $approvalInitiatedOn = $approvalInitiatedOn.ToString("yyyy-MM-dd HH:mm:ss")
            }

            if (!$approvalComment)
            {
                $approvalComment += "APPROVAL COMMENT IS MISSING!!! PLEASE ADD COMMENT TO APPROVAL."
            }

            $fields += @{
                title = $approvalComment;
                value = ">Approved by *<mailto:$approverUniqueName|$approverName>* on _$approvedOn`_ (initiated on _$approvalInitiatedOn`_)";
                short = $false
            }

            if ($approverName)
            {
                $pipelineStartedBy += ", approved by <mailto:$approverUniqueName|$approverName>"
            }
        }
    } 
    else
    {
        $fields += @{
            title = "No approval found for the deploy stage $DeployStageName";
            value = ">Please check if the approvals are enabled for the deploy environment";
            short = $false
        }
    }

    # Get change details for the deployment
    $url = "$projectUri/_apis/build/builds/$buildId/changes?`$top=10&api-version=7.0"

    if ($ShowDebugInfo -eq $true)
    {
        Write-Output "Get build changes API result:"
        Write-Output "API Uri: $url"
    }

    $result = Invoke-RestMethod -Uri $url -Headers $azureAuthHeaders -ContentType $contentTypeJson -Method Get

    if ($ShowDebugInfo -eq $true)
    {
        Write-Output "API result:"
        Write-Output $result | ConvertTo-Json
    }

    $fields += @{
        title = "Changes (top 10)";
        short = $false
    }

    foreach ($item in $result.value)
    {
        $changeMessage = $item.message
        $changeTimestamp = $item.timestamp
        $changeAuthorName = $item.author.displayName
        $changeAuthorUniqueName = $item.author.uniqueName
        $changeUri = $item.displayUri

        if ($changeTimestamp)
        {
            $changeTimestamp = $changeTimestamp.ToString("yyyy-MM-dd HH:mm:ss")
        }

        # Add commit as separate field (section)
        $fields += @{
            value = "- *$changeMessage* _(<$changeUri|commit> by <mailto:$changeAuthorUniqueName|$changeAuthorName> on $changeTimestamp)_";
            short = $false
        }

        # Get last commit author as executor when pipeline is executed automatically
        if (!$pipelineStartedBy)
        {
            $pipelineStartedBy = "Automatically started, last author $changeAuthorName"
        }
    }
}
elseif ($DeployState -eq "finished")
{
    $jobIdentifier = $DeployJobIdentifier

    $deploySuffix = ".Deploy"
    $defaultSuffix = ".__default"

    if (!$jobIdentifier)
    {
        throw "Parameter 'deployJobIdentifier' must be set for deployState 'finished' to get the result for deploy job via Azure DevOps API."
    }
    elseif ((-not $jobIdentifier.EndsWith($deploySuffix)) -and (-not $jobIdentifier.EndsWith($defaultSuffix)))
    {
        $jobIdentifier += $defaultSuffix
    }

    # If stage name is not set, then add stage name in the beginning
    if ($jobIdentifier.Split('.').count -lt 3)
    {
        $jobIdentifier = "$DeployStageName.$jobIdentifier"
    }

    $url = "$projectUri/_apis/build/builds/$buildId/timeline?api-version=7.0"

    if ($ShowDebugInfo -eq $true)
    {
        Write-Output "Get build timeline API result:"
        Write-Output "API Uri: $url"
    }


    # Get timeline aka stages, jobs and tasks for the build
    $result = Invoke-RestMethod -Uri $url -Headers $azureAuthHeaders -ContentType $contentTypeJson -Method Get
    
    if ($ShowDebugInfo -eq $true)
    {
        Write-Output "API result:"
        Write-Output $result | ConvertTo-Json
    }

    # Find the deploy job from result, match by identifier, type (Job) and state (completed)
    $job = $result.records | Where-Object {($_.identifier -eq $jobIdentifier) -and ($_.type -eq "Job") -and ($_.state -eq "completed")}
    
    $deployResult = $job.result

    # If no job result could be fetched, throw error
    if (!$deployResult)
    {
        throw "Deploy result could fetched for job '$jobIdentifier' via API ($url)"
    }

    $title += " with status $deployResult"

    if (($deployResult -eq "canceled") -or ($deployResult -eq "Canceled"))
    {
        $color = 'warning'
    } 
    elseif (($deployResult -eq "partial") -or ($deployResult -eq "SucceededWithIssues"))
    {
        $color = 'warning'
    }
    elseif (($deployResult -eq "failed") -or ($deployResult -eq "Failed"))
    {
        $color = 'danger'
    }

    # Get job duraiton from startTime and finishTime properties
    $duration = $job.finishTime - $job.startTime

    $fields += @{
        title = 'Deploy duration';
        value = $duration.ToString();
        short = $true
    }

    $jobId = $job.id
    $errorItems = $result.records | Where-Object {($_.parentId -eq $jobId) -and ($_.errorCount -gt 0)}

    foreach ($item in $errorItems)
    {
        $itemType = $item.type
        $itemName = $item.name
        $logUrl = $item.log.url

        $errorMessages = ""
        foreach ($issue in $item.issues)
        {
            if ($issue.type -ne "error")
            {
                continue
            }
            $issueMessage = $issue.message
            $issueLogFileNr = $issue.data.logFileLineNumber

            $errorMessages += "`n>Error, line $issueLogFileNr`: _$issueMessage`_"
        }

        $fields += @{
            title = "Error(s) in $itemType '$itemName'";
            value = "$errorMessages`nSee <$logUrl|log output> for more error details";
            short = $false
        }
    }
}

$buildUrl = "$projectUri/_build/results?buildId=$buildId"

$deployStatusMessage = $DeployState
if ($deployResult)
{
    $deployStatusMessage += " ($deployResult)"
}
$message = "Deploy *$ServiceName* (version <$buildUrl|$buildNumber>) *$deployStatusMessage*"

$slackMessageBody = @{
    channel = $ChannelId;
    attachments = @(
        @{
            mrkdwn = $true;
            mrkdwn_in = @('text', 'pretext');
            color = $color;
            #title = "$title for service $ServiceName (version <$buildUrl|$buildNumber>)";
            #title_link = $buildUrl;
            pretext = $message;
            footer = $pipelineStartedBy;
            fields = $fields
        }
    )
}

if ($InfoMessage)
{
    $slackMessageBody += @{
        message = $InfoMessage
    }
}

if ($DeployStartedSlackMessageId)
{
    $slackMessageBody += @{
        thread_ts = $DeployStartedSlackMessageId;
        reply_broadcast = $true
    }
}

$bodyJson = ConvertTo-Json $slackMessageBody -Depth 10
Write-Output "Slack API message body: $bodyJson"

$slackAuthHeaders = @{ Authorization = "Bearer $SlackAuthToken" }
$slackResponse = Invoke-WebRequest -Uri $SlackApiUri -Body $bodyJson -ContentType $contentTypeJson -Headers $slackAuthHeaders -Method Post

# Get Slack post response and message id, see https://api.slack.com/methods/chat.postMessage
if (($DeployState -eq "started") -and $slackResponse -and $slackResponse.Content)
{
    $slackJson = ConvertFrom-Json -InputObject $slackResponse.Content
    if ($slackJson.ok -eq "true")
    {
        $slackResponseMessageId = $slackJson.ts
        Write-Host "##vso[task.setvariable variable=DeploySlackMessageId;isOutput=true]$slackResponseMessageId"
        Write-Host "Slack response, posted message id $slackResponseMessageId"
    }
    else
    {
        throw "Error posting deploy notification to Slack: $slackJson"
    }
}

# If additional Slack channel id is specified, send message to this channel as well
if ($AdditionalChannelId)
{
    $slackMessageBody['channel'] = $AdditionalChannelId
    $bodyJson = ConvertTo-Json $slackMessageBody -Depth 10

    Invoke-WebRequest -Uri $SlackApiUri -Body $bodyJson -ContentType $contentTypeJson -Headers $slackAuthHeaders -Method POST
}
