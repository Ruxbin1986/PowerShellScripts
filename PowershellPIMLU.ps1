# Connect to Azure and Microsoft Graph
Connect-AzAccount
Connect-MgGraph -Scopes "User.Read.All", "RoleManagement.Read.All", "Directory.Read.All"

# Define the group ID to check membership
$groupId = "your-group-id-here"

# Define an array of user objects
$users = @(
    [PSCustomObject]@{UserPrincipalName="user1@yourtenant.com"},
    [PSCustomObject]@{UserPrincipalName="user2@yourtenant.com"}
)

# Get all subscriptions in the tenant
$allSubscriptions = Get-AzSubscription

# Get all directory roles
$directoryRoles = Get-MgDirectoryRole

# Create a function to map role IDs to role names
function Get-RoleName {
    param (
        [string]$roleId
    )
    $role = $directoryRoles | Where-Object { $_.Id -eq $roleId }
    return $role.DisplayName
}

# Create a list to hold the results
$results = @()

foreach ($user in $users) {
    $userPrincipalName = $user.UserPrincipalName

    Write-Output "Checking group membership for user: $userPrincipalName"

    # Check if the user is a member of the specified group
    $userId = (Get-MgUser -UserPrincipalName $userPrincipalName).Id
    $groupMembers = Get-MgGroupMember -GroupId $groupId -All
    $isMember = $groupMembers | Where-Object { $_.Id -eq $userId }

    $isMemberFlag = $false
    if ($isMember) {
        $isMemberFlag = $true
    }

    Write-Output "  User is a member of the specified group: $isMemberFlag"

    # Check if the user has any access to any Azure subscriptions
    $subscriptionDetails = @()
    foreach ($subscription in $allSubscriptions) {
        $roleAssignments = Get-AzRoleAssignment -Scope "/subscriptions/$($subscription.Id)" -SignInName $userPrincipalName -ErrorAction SilentlyContinue
        if ($roleAssignments) {
            foreach ($roleAssignment in $roleAssignments) {
                $roleName = $roleAssignment.RoleDefinitionName
                $groupName = $roleAssignment.Scope
                $subscriptionDetails += [PSCustomObject]@{
                    SubscriptionName = $subscription.Name
                    RoleName = $roleName
                    GroupName = $groupName
                }
            }
        }
    }

    if (-not $subscriptionDetails) {
        $subscriptionDetails = [PSCustomObject]@{
            SubscriptionName = "No access"
            RoleName = ""
            GroupName = ""
        }
    }

    # Check if the user is assigned any direct roles in the tenant
    $directRoles = Get-MgUserAppRoleAssignment -UserId $userId -ErrorAction SilentlyContinue
    $roleNames = @()
    if ($directRoles) {
        $roleNames = $directRoles | ForEach-Object { Get-RoleName -roleId $_.AppRoleId }
    }
    if (-not $roleNames) {
        $roleNames = "No direct roles"
    }

    # Check if the user is eligible for any PIM roles
    $pimRoles = Get-MgRoleManagementDirectoryRoleAssignment -Filter "principalId eq '$userId' and roleAssignmentScheduleState eq 'Eligible'"
    $pimRoleNames = @()
    if ($pimRoles) {
        $pimRoleNames = $pimRoles | ForEach-Object { Get-RoleName -roleId $_.RoleDefinitionId }
    }
    if (-not $pimRoleNames) {
        $pimRoleNames = "No PIM roles"
    }

    # Create an object for the result
    $result = [PSCustomObject]@{
        UserPrincipalName = $userPrincipalName
        IsGroupMember = $isMemberFlag
        Subscriptions = ($subscriptionDetails | ForEach-Object {
            "$($_.SubscriptionName) ($($_.RoleName) - $($_.GroupName))"
        }) -join ", "
        AssignedRoles = ($roleNames -join ", ")
        PIMAssignments = ($pimRoleNames -join ", ")
    }

    # Add the result to the list
    $results += $result
}

# Export the results to a CSV file
$results | Export-Csv -Path "UserAccessReport.csv" -NoTypeInformation

# Disconnect from Azure and Microsoft Graph
Disconnect-AzAccount
Disconnect-MgGraph

Write-Output "User access report exported to UserAccessReport.csv"
