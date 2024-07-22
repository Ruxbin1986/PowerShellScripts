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

# Get all role definitions
$roleDefinitions = Get-MgDirectoryRole

# Create a function to map role IDs to role names
function Get-RoleName {
    param (
        [string]$roleId
    )
    $role = $roleDefinitions | Where-Object { $_.Id -eq $roleId }
    return $role.DisplayName
}

# Create a list to hold the results
$results = @()

foreach ($user in $users) {
    $userPrincipalName = $user.UserPrincipalName

    Write-Output "Checking group membership for user: $userPrincipalName"

    # Check if the user is a member of the specified group
    $userId = (Get-MgUser -UserPrincipalName $userPrincipalName).Id
    $isMember = Get-MgGroupMember -GroupId $groupId -UserId $userId -ErrorAction SilentlyContinue
    
    if ($isMember) {
        Write-Output "  User is a member of the specified group. Checking access details..."

        # Check if the user has any access to any Azure subscriptions
        $subscriptionNames = @()
        foreach ($subscription in $allSubscriptions) {
            $roleAssignments = Get-AzRoleAssignment -Scope "/subscriptions/$($subscription.Id)" -SignInName $userPrincipalName -ErrorAction SilentlyContinue
            if ($roleAssignments) {
                $subscriptionNames += $subscription.Name
            }
        }
        if (-not $subscriptionNames) {
            $subscriptionNames = "No access"
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
        $pimRoles = Get-MgPrivilegedRoleAssignment -Filter "principalId eq '$userId' and assignmentState eq 'Eligible'"
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
            Subscriptions = ($subscriptionNames -join ", ")
            AssignedRoles = ($roleNames -join ", ")
            PIMAssignments = ($pimRoleNames -join ", ")
        }

        # Add the result to the list
        $results += $result
        $result
        $results.count
    } else {
        Write-Output "  User is not a member of the specified group. Skipping..."
    }
}
