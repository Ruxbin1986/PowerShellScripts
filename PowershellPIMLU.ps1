$Scopes = @(
    "RoleManagementPolicy.Read.AzureADGroup",
    "AuditLog.Read.All",
    "Directory.Read.All",
    "Group.Read.All",
    "User.Read.All"
)

Connect-MgGraph -Scopes $Scopes

$EligibleEntraUserData = @()
$EligibleEntraGroupData = @()

$EligileAssignments = Get-MgRoleManagementDirectoryRoleEligibilityScheduleInstance -ExpandProperty "*" -All

foreach($Role in $EligileAssignments) {
    if($Role.Principal.AdditionalProperties.'@odata.type' -eq "#microsoft.graph.user") {
        # Get the last sign-in for the user
        $auditLogs = Get-MgAuditLogSignIn -Filter "userId eq '$($Role.Principal.AdditionalProperties.id)' and activityDisplayName eq 'Activate role'" -Top 1
        $lastUsed = if ($auditLogs) { $auditLogs[0].createdDateTime } else { "None" }

        $UserProperties = [pscustomobject]@{
            DisplayName = $Role.Principal.AdditionalProperties.displayName
            UserPrincipalName = $Role.Principal.AdditionalProperties.userPrincipalName
            AccountEnabled = $Role.Principal.AdditionalProperties.accountEnabled
            StartDateTime = $Role.StartDateTime
            EndDateTime = $Role.EndDateTime
            MemberType = $Role.MemberType
            RoleName = $Role.RoleDefinition.DisplayName
            RoleID = $Role.RoleDefinition.Id
            LastUsed = $lastUsed
        }
        $EligibleEntraUserData += $UserProperties
    }
    else {
        $GroupProperties = [pscustomobject]@{
            DisplayName = $Role.Principal.AdditionalProperties.displayName
            IsAssignableToRole = $Role.Principal.AdditionalProperties.isAssignableToRole
            StartDateTime = $Role.StartDateTime
            EndDateTime = if ($null -eq $Role.EndDateTime) { "Permanent" } else { $Role.EndDateTime }
            MemberType = $Role.MemberType
            RoleName = $Role.RoleDefinition.DisplayName
            RoleID = $Role.RoleDefinition.Id
        }
        $EligibleEntraGroupData += $GroupProperties

        # Get group members
        $groupMembers = Get-MgGroupMember -GroupId $Role.Principal.AdditionalProperties.id -All
        foreach ($member in $groupMembers) {
            if ($member.'@odata.type' -eq '#microsoft.graph.user') {
                # Get the last sign-in for the group member
                $auditLogs = Get-MgAuditLogSignIn -Filter "userId eq '$($member.id)' and activityDisplayName eq 'Activate role'" -Top 1
                $lastUsed = if ($auditLogs) { $auditLogs[0].createdDateTime } else { "None" }

                $UserProperties = [pscustomobject]@{
                    DisplayName = $member.DisplayName
                    UserPrincipalName = $member.UserPrincipalName
                    Group = $Role.Principal.AdditionalProperties.displayName
                    LastUsed = $lastUsed
                }
                $EligibleEntraUserData += $UserProperties
            }
        }
    }
}

# Print out the details
$EligibleEntraUserData
$EligibleEntraGroupData

# Disconnect from Microsoft Graph
Disconnect-MgGraph
