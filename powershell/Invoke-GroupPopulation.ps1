# Populate static groups based on user department and office location.
# Simulates dynamic group logic for tenants without Entra ID P2.

Connect-MgGraph -Scopes "User.ReadWrite.All","Group.ReadWrite.All"

# Define your groups and their membership rules
$rules = @(
    @{ Group = "OKC-Players-ActiveRoster"; Department = "Players";     Office = "Paycom Center" },
    @{ Group = "OKC-Staff-Coaching";       Department = "Coaching";    Office = "Paycom Center" },
    @{ Group = "OKC-Staff-Medical";        Department = "Medical";     Office = "Paycom Center" },
    @{ Group = "OKC-FrontOffice";          Department = "FrontOffice"; Office = "Paycom Center" },
    @{ Group = "NYK-Players-ActiveRoster"; Department = "Players";     Office = "Madison Square Garden" },
    @{ Group = "NYK-Staff-Coaching";       Department = "Coaching";    Office = "Madison Square Garden" },
    @{ Group = "NYK-Staff-Medical";        Department = "Medical";     Office = "Madison Square Garden" },
    @{ Group = "NYK-FrontOffice";          Department = "FrontOffice"; Office = "Madison Square Garden" }
)

foreach ($r in $rules) {
    Write-Host "`nProcessing: $($r.Group)"

    # Create the group if it doesn't exist
    $group = Get-MgGroup -Filter "displayName eq '$($r.Group)'" -ErrorAction SilentlyContinue
    if (-not $group) {
        $group = New-MgGroup -DisplayName $r.Group `
            -MailEnabled:$false `
            -MailNickname ($r.Group -replace "-","") `
            -SecurityEnabled:$true
        Write-Host "  Created group"
    }

    # Find matching users and add them to the group
    $users = Get-MgUser -Filter "department eq '$($r.Department)' and officeLocation eq '$($r.Office)'" -All

    foreach ($user in $users) {
        try {
            New-MgGroupMember -GroupId $group.Id -DirectoryObjectId $user.Id -ErrorAction Stop
            Write-Host "  Added: $($user.DisplayName)"
        } catch {
            Write-Host "  Skipped (already member): $($user.DisplayName)"
        }
    }
}

Write-Host "`nDone."