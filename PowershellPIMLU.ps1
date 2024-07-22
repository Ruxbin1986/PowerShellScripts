# Connect to Azure and Microsoft Graph
Connect-AzAccount
Connect-MgGraph -Scopes "User.Read.All", "RoleManagement.Read.All", "Directory.Read.All"

# Define an array of user objects
$users = @(
    [PSCustomObject]@{UserPrincipalName="user1@yourtenant.com"},
    [PSCustomObject]@{UserPrincipalName="user2@yourtenant.com"}
)

# Create a list to hold the results
$results = @()

foreach ($user in $users) {
    $userPrincipalName = $user.UserPrincipalName

    Write-Output "Checking access for user: $userPrincipalName"

    # Check if the user has any access to any Azure subscriptions
    $subscriptions = Get-AzRoleAssignment -SignInName $userPrincipalName -ErrorAction SilentlyContinue
    $subscriptionNames = @()
    if ($subscriptions) {
        $subscriptionNames = $subscriptions | ForEach-Object { $_.Scope }
    }

    # Check if the user is assigned any direct roles in the tenant
    $userId = (Get-MgUser -UserPrincipalName $userPrincipalName).Id
    $directRoles = Get-MgUserAppRoleAssignment -UserId $userId -ErrorAction SilentlyContinue
    $roleNames = @()
    if ($directRoles) {
        $roleNames = $directRoles | ForEach-Object { $_.AppRoleId } # Needs mapping to human-readable names
    }

    # Check if the user is eligible for any PIM roles
    $pimRoles = Get-MgPrivilegedRoleAssignment -Filter "principalId eq '$userId' and assignmentState eq 'Eligible'"
    $pimRoleNames = @()
    if ($pimRoles) {
        $pimRoleNames = $pimRoles | ForEach-Object { $_.RoleDefinitionId } # Needs mapping to human-readable names
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
}

# Export the results to a CSV file
$results | Export-Csv -Path "UserAccessReport.csv" -NoTypeInformation

# Disconnect from Azure and Microsoft Graph
Disconnect-AzAccount
Disconnect-MgGraph

Write-Output "User access report exported to UserAccessReport.csv"
