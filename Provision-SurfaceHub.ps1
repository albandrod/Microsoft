#Requires -Modules @{ModuleName="AzureADPreview";ModuleVersion="2.0.2.85"}

#Pre-Reqs
##Exchange access to create mailbox
##AAD access to create group, license user
##Azure subscription with rights to create resources

#This script will
#Create Surface Hub account
#Set location usage & Meeting Room license
#Create Dynamic AAD Device Group on OS = SurfaceHub
#Provision Azure Log Analytics workspace and retrieve customerID & key, Install SurfaceHub Solution
#Configure Intune policies for Surface Hub and set LA tenant info

#PowerShell modules required
#AzureADPreview
#Azure
#Microsoft.Graph.Intune

#User Input Required
$Credential = Get-Credential
$UPN = "Test03252020-20@netrixebc.com"
$usagelocation = "US"
$workspacename = "netrixebchub"
$ResourceGroupName = "USE-SurfaceHub-RG"
$RGLocation = "eastus"
$emailowner = "rlillyadmin@netrixebc.com"

#Calculated Variables
$alias = $upn.split("@")[0]
$password = (New-Guid).tostring()
$params1 = @{"OwnerEmail"="$emailowner"}

#Connect to resources
$365Session = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri https://ps.outlook.com/powershell -Credential $Credential -Authentication Basic –AllowRedirection
$ImportResults = Import-PSSession $365Session -AllowClobber
Connect-AzureAD
Connect-MSGraph -Credential $Credential
Add-AzAccount
$subscription = get-azsubscription |out-gridview -passthru
Select-azsubscription -subscription $subscription

#Create Surface Hub account
New-Mailbox -MicrosoftOnlineServicesID $UPN -Alias $alias -Name $UPN -Room -EnableRoomMailboxAccount $true -RoomMailboxPassword (ConvertTo-SecureString  -String "$password" -AsPlainText -Force)
Start-Sleep 15
Set-CalendarProcessing -Identity $UPN -AutomateProcessing AutoAccept -AddOrganizerToSubject $false –AllowConflicts $false –DeleteComments $false -DeleteSubject $false -RemovePrivateProperty $false -AddAdditionalResponse $true -AdditionalResponse "This room is equipped with a Surface Hub"
$user = Get-AzureADUser -SearchString "$($alias)"

#Set Usage Location
Set-AzureADUser -ObjectId $user.ObjectId -UsageLocation $usagelocation

# Create the objects we'll need to add and remove Meeting Room license
$license = New-Object -TypeName Microsoft.Open.AzureAD.Model.AssignedLicense
$licenses = New-Object -TypeName Microsoft.Open.AzureAD.Model.AssignedLicenses

# Find the SkuID of the license we want to add - in this example we'll use the O365_BUSINESS_PREMIUM license
$license.SkuId = (Get-AzureADSubscribedSku | Where-Object -Property SkuPartNumber -Value "MEETING_ROOM" -EQ).SkuID

# Set the Office license as the license we want to add in the $licenses object
$licenses.AddLicenses = $license

# Call the Set-AzureADUserLicense cmdlet to set the license.
Set-AzureADUserLicense -ObjectId $user.objectid -AssignedLicenses $licenses

#Create AAD Device Group
$group = New-AzureADMSGroup -DisplayName "Surface Hub Device Group" -Description "Surface Hub Devices" -MailEnabled $False -MailNickName "SurfaceHubDeviceGroup" -SecurityEnabled $True -GroupTypes "DynamicMembership" -MembershipRule "(device.deviceOSType -eq ""SurfaceHub"")" -MembershipRuleProcessingState "On"

#Provision Azure Log Analytics workspace
New-AzResourceGroup -Name $ResourceGroupName -Location $RGLocation -Tag $params1
$LAWorkspace = New-AzOperationalInsightsWorkspace -ResourceGroupName $ResourceGroupName -Name $workspacename -Location $RGLocation -Sku standalone
$LAWorkspaceCustomerId = $LAWorkspace.CustomerId.Guid
$LAWorkspaceKey = (Get-AzOperationalInsightsWorkspaceSharedKey -ResourceGroupName $ResourceGroupName -Name $workspacename).PrimarySharedKey
Set-AzOperationalInsightsIntelligencePack -ResourceGroupName $ResourceGroupName -WorkspaceName $workspacename -IntelligencePackName SurfaceHub -Enabled $true

#Configure Intune policies
$IntuneHubPolicy1 = New-IntuneDeviceConfigurationPolicy -displayName "Surface Hub Microsoft Teams" -windows10TeamGeneralConfiguration -azureOperationalInsightsBlockTelemetry $false -azureOperationalInsightsWorkspaceId $LAWorkspaceCustomerId -azureOperationalInsightsWorkspaceKey $LAWorkspaceKey -welcomeScreenMeetingInformation showOrganizerAndTimeAndSubject -maintenanceWindowStartTime 00:00:00.0000000 -maintenanceWindowDurationInHours 4
New-IntuneDeviceConfigurationPolicyAssignment -deviceConfigurationId $IntuneHubPolicy1.id -target (New-Object PSObject -Property ([Ordered]@{'@odata.type' = '#microsoft.graph.groupAssignmentTarget'; groupId = $group.Id}))

#$IntuneHubPolicy2 = New-IntuneDeviceConfigurationPolicy -displayName "Surface Hub Microsoft Teams" -omaSettings (New-Object PSObject -Property ([Ordered]@{'@odata.type' = '#microsoft.graph.omaSettingInteger'; 'displayName' = 'Teams Mode'; 'omaUri' = './Vendor/MSFT/SurfaceHub/Properties/SurfaceHubMeetingMode'; 'value' = '1'}))
#New-IntuneDeviceConfigurationPolicyAssignment -deviceConfigurationId $IntuneHubPolicy2.id -target (New-Object PSObject -Property ([Ordered]@{'@odata.type' = '#microsoft.graph.groupAssignmentTarget'; groupId = $group.Id}))

##Clean-up
#Remove-Mailbox -Identity $UPN -Confirm
#Remove-AzureADMSGroup -Id $group.Id
#Remove-AzResourceGroup -Name $ResourceGroupName
#Remove-IntuneDeviceConfigurationPolicy -deviceConfigurationId $IntuneHubPolicy1.deviceConfigurationId