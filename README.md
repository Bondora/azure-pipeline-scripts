# Introduction 

Pipeline scripts that can be used in your [Azure pipeline templates](https://github.com/Bondora/azure-pipeline-templates) and also can be used from other pipelines.

# How to contribute

1. Create new feature branch
2. Use the branch reference (`ref: refs/heads/branch-name`) in pipeline to test out changes in this branch, see below for examples
3. Do the changes, push, create PR
4. Merge to main branch
5. Add *new version tag* (vN+1) if there are breaking changes to exiting template(s) or *move version tag* (set same tag) to latest commit.

## Breaking changes
Avoid any breaking changes (interface aka required parameters or changing file name or location) as much as possible.
When adding parameters to scripts, add default value, so that pipelines using the script do not fail.
Do not rename the script files or move to another directory. This will break the reference from pipelines using the scripts.

Adding new script file is not breaking change but new feature. As soon as any pipeline starts using the script you risk breaking the pipeline when changing the script interface (name and required parameters).

### When you need to do breaking changes
1. You have to find all the usages for the script and change those pipelines, when only few pipelines use it.
2. Add new version tag in format of vX (like v1 or v2) where X is integer. Then you can use the specific tag reference and reference new and old version (tag) in pipelines.

## After adding non-breaking changes
Move the tag to new commit (tag the commit with same version) after merging the changes to main branch so that pipelines referencing specific tag version get the changes.

## Using predefined build/system variables in scripts

See [Pipeline predefined variables](https://learn.microsoft.com/en-us/azure/devops/pipelines/build/variables?view=azure-devops&tabs=yaml) for documentation.

In YAML pipelines, you can reference predefined variables as environment variables. For example, the variable `Build.ArtifactStagingDirectory` becomes the variable `BUILD_ARTIFACTSTAGINGDIRECTORY`.

### Using System.AccessToken in scripts

See [documentation](https://learn.microsoft.com/en-us/azure/devops/pipelines/build/variables?view=azure-devops&tabs=yaml#systemaccesstoken) about how you have to either pass the access token to script or specifically declare environment variable in pipeline, so that you can use it as envvar from script.

```yaml
steps:
  - bash: echo This script could use $SYSTEM_ACCESSTOKEN
    env:
      SYSTEM_ACCESSTOKEN: $(System.AccessToken)
  - powershell: | 
      Write-Host "This is a script that could use $env:SYSTEM_ACCESSTOKEN"
      Write-Host "$env:SYSTEM_ACCESSTOKEN = $(System.AccessToken)"
    env:
      SYSTEM_ACCESSTOKEN: $(System.AccessToken)
```

# How to use scripts in other repositories

## Inline (only when scripts repository is in same Azure DevOps organization):

Set `@refs/tags/v1` at the end of the repository path to use specific tag (in this case named `v1`). This is needed so that breaking changes to main branch do not break the references.

You can also specify feature branch (`@refs/heads/feature-branch-name`) when testing new or changed scripts.

```yaml
stages:
- stage:
  jobs:
  - job:
    steps:
    - checkout: git://{azure-devops-project-name}/azure-pipeline-scripts@refs/tags/v1
    - task: PowerShell@2
      inputs:
        filePath: scripts/my-script.ps1
        arguments: >
          -Arg1 "value1"
          -Arg2 "value2"
```

## Using resources:

```yaml
resources:
  repositories:
  - repository: scripts
    type: git
    name: {azure-devops-project-name}/azure-pipeline-scripts
    ref: refs/tags/v1

stages:
- stage:
  jobs:
  - job:
    steps:
    - checkout: scripts
    - bash: echo 'yay!'
```

# How to use scripts

## Script 'scripts/notify-deploy-to-slack.ps1'

Used to send deploy notifications to slack using Slack API and Azure REST API to get information about pipeline deployment state.

See template [jobs/notify-deploy-to-slack.yml](https://github.com/Bondora/azure-pipeline-templates/blob/main/jobs/notify-deploy-to-slack.yml) for more information.

```yaml
# Lines omitted to shorten the sample
jobs:
- job: NotifySlack_${{ parameters.deployState }}
  variables:
  - name: slackChannelId
    value: $[coalesce('${{ parameters.slackChannelId }}', variables.slackDefaultDeployChannelId)]
  - name: deployStartedSlackMessageId
    ${{ if eq(parameters.deployState, 'finished') }}:
      value: $[dependencies.NotifySlack_started.outputs['SendSlackNotification_DeployState_started.DeploySlackMessageId']]
    ${{ if ne(parameters.deployState, 'finished') }}:
      value: ''
  - group: 'slack-variable-group-name'
  steps:
  - checkout: git://${{ variables['System.TeamProject'] }}/azure-pipeline-scripts@refs/tags/v1
  - task: PowerShell@2
    name: SendSlackNotification_DeployState_${{ parameters.deployState }}
    displayName: 'Send Slack notification (${{ parameters.deployState }})'
    condition: ${{ parameters.condition }}
    timeoutInMinutes: ${{ parameters.timeoutInMinutes }}
    inputs:
      filePath: scripts/notify-deploy-to-slack.ps1
      arguments: >
        -DeployState "${{ parameters.deployState }}"
        -ServiceName "${{ parameters.serviceName }}"
        -SlackApiUri "$(slackApiUri)"
        -SlackAuthToken "$(slackAuthToken)"
        -ChannelId "$(slackChannelId)"
        -SystemAccessToken "$(System.AccessToken)"
        -AdditionalChannelId "${{ parameters.additionalSlackChannelId }}"
        -InfoMessage "${{ parameters.infoMessage }}"
        -DeployJobIdentifier "${{ parameters.deployJobIdentifier }}"
        -DeployStartedSlackMessageId "$(deployStartedSlackMessageId)"
        -ShowDebugInfo 1
      failOnStderr: true
```

# References

- [Azure Pipeline Templates](https://github.com/Bondora/azure-pipeline-templates)
- [Pipeline predefined variables](https://learn.microsoft.com/en-us/azure/devops/pipelines/build/variables?view=azure-devops&tabs=yaml)
- [Set variables in scripts](https://learn.microsoft.com/en-us/azure/devops/pipelines/process/set-variables-scripts?view=azure-devops&tabs=bash)
- [Check out multiple repositories in your pipeline](https://learn.microsoft.com/en-us/azure/devops/pipelines/repos/multi-repo-checkout?view=azure-devops)
