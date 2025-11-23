###  Reddit Access  [ API ]
##  Import the PSRAW - PowerShell Reddit API Wrapper Module ##
    # PSRAW on GitHub
        # https://github.com/markekraus/PSRAW/blob/staging/README.md
    # DOCS
        # https://psraw.readthedocs.io/en/latest/Examples/Quickstart/#register-a-script-application-on-reddit

####### PSRAW set-up #######
# ------------------------------------------------------------
# Install-Module PSRAW
# Import-Module PSRAW

#######  Connect to Reddit ######
Connect-Reddit

# 'irr' = Invoke-RedditRequest is a PSRAW command (similar to invoke-webrequest
irr https://oauth.reddit.com/api/v1/me | Select-Object -ExpandProperty ContentObject

# OAuth access
$OAuthTokenSaveLocation = "<save location>"
Export-RedditOAuthToken $OAuthTokenSaveLocation
Import-RedditOAuthToken
# end connect to reddit
####################################################################################


########  Get Reddit Access token (needed to delete comments and more) ######
# ------------------------------------------------------------
# Reddit app credentials
cls
$ClientID       = Read-Host -Prompt "Enter your Reddit application Client ID..."
cls
$ClientSecret   = Read-Host -Prompt "Enter your Reddit application Client Secret..."
cls
# Your Reddit username and password (Reddit API requires both)
$RedditUser     = Read-Host -Prompt "Enter Reddit username..."
cls
$RedditPassword = Read-Host -Prompt "Enter Reddit password..."   
cls

# Build Basic Auth header
$pair = "{0}:{1}" -f $ClientID, $ClientSecret
$basicAuth = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($pair))
$Headers = @{
    "Authorization" = "Basic $basicAuth"
    "User-Agent"    = "MyRedditScript/1.0 by $RedditUser"
}
$Body = @{
    grant_type = "password"
    username   = $RedditUser
    password   = $RedditPassword
}

# Get the access token
$TokenResponse = Invoke-RestMethod `
    -Method Post `
    -Uri "https://www.reddit.com/api/v1/access_token" `
    -Headers $Headers `
    -Body $Body
$TokenResponse
# End get reddit access token
####################################################################################



#######  Get user account info ######
# ------------------------------------------------------------
$Uri = 'https://oauth.reddit.com/api/v1/me'
$reddit = Invoke-RedditRequest -Uri $Uri 
$reddit_content = $reddit.contentobject  
$reddit_content
# End get reddit user account info   
####################################################################################                                                       


#######  Get subreddit ######
# ------------------------------------------------------------
$subreddit = $reddit_content | select-object -ExpandProperty subreddit
$subreddit
# end get subreddit
####################################################################################


#######  Get inbox messages ######
# ------------------------------------------------------------
$Uri = 'https://oauth.reddit.com/message/inbox'
$Response = Invoke-RedditRequest -Uri $Uri
$Messages = $response.ContentObject.data.children.data
# end get inbox messages
####################################################################################


#######  Get comments ######
# ------------------------------------------------------------
$PostArray = @()
$uriPage = $null
$redditUserName = Read-host -prompt "Enter your Reddit user name..."  # use 'OPDontKnow', not 'u/OPDontKnow'

do {
    $uri = "https://oauth.reddit.com/user/$redditUserName/comments.json?after=$uriPage"
    $response = Invoke-RedditRequest -Uri $uri

    foreach ($post in $response.ContentObject.data.children) {
        # Determine type from the kind
        $Type = switch ($post.kind) {
            't1' { 'Comment' }
            't3' { 'Post' }
            default { 'Unknown' }
        }

        # Correct IDs
        $ItemID       = "$($post.kind)_$($post.data.id)"   # full ID of this item
        $ParentPostID = if ($Type -eq 'Comment') { $post.data.link_id } else { $ItemID }  # parent post ID

        # Correct edited handling
        $EditedDate = if ($post.data.edited -is [bool] -and $post.data.edited -eq $false) {
            'Never'
        } else {
            ((Get-Date -Date "01-01-1970") + ([System.TimeSpan]::FromSeconds($post.data.edited))).ToString("yyyy-MM-dd HH:mm:ss")
        }

        # Convert creation date
        $CreatedDate = ((Get-Date -Date "01-01-1970") + ([System.TimeSpan]::FromSeconds($post.data.created_utc))).ToString("yyyy-MM-dd HH:mm:ss")


        $PostArray += [pscustomobject]@{
            Type          = $Type
            ItemID        = $ItemID
            ParentPostID  = $ParentPostID
            Author        = $post.data.author
            AuthorID      = $post.data.author_fullname
            DateTime      = $CreatedDate
            Edited        = $EditedDate
            Gildings      = $post.data.gildings
            Permalink     = $post.data.permalink
            Subreddit     = $post.data.subreddit_name_prefixed
            PostAuthor    = $post.data.link_author
            PostTitle     = $post.data.link_title
            Score         = [int]$post.data.score
            Message       = ($post.data.selftext + $post.data.url + $post.data.body)
        }

        # Update the pagination token for the next page
        $uriPage = $response.ContentObject.data.after
    }
} while ($uriPage -ne $null)

### $itemID value should be used to delete comments (as shown below)
# end get comments
####################################################################################


####### Delete multiple comments ######
# ------------------------------------------------------------
# Your OAuth token (must include: edit, identity)
    ### To get the access token, see listing above "Get Reddit Access token"
    ### Should only need to run once.  Expires in 24hrs.
$AccessTokenRaw = Read-Host -Prompt "Enter your Reddit Access token..."
$AccessToken = $AccessTokenRaw.Trim() -replace "`r","" -replace "`n",""

foreach($post in $postArray){
    # The fullname of the comment you want to delete (starts with t1_)
    $CommentFullname = $post.itemID
    $commentMsg = $post.message
    
    # Endpoint
    $Uri = "https://oauth.reddit.com/api/del"

    # Body must be application/x-www-form-urlencoded
    $Body = @{
        id = $CommentFullname
    }

    # Headers including bearer token
    $Headers = @{
        "Authorization" = "bearer $AccessToken"
        "User-Agent"    = "MyRedditApp/1.0 by <your_username>"
    }

    # Make the request
    $response = Invoke-RestMethod -Uri $Uri -Method Post -Headers $Headers -Body @{ id = $CommentFullname }
    $response  # should be null
    
    start-sleep -s 1

    # verify comment has been deleted
    Write-Host "`nChecking deletion status of your comment... `n`t [ $commentMsg ]"
    $CommentID = $commentFullname
    $deleteStatus = Invoke-RestMethod -Method Get -Uri "https://oauth.reddit.com/api/info/?id=$CommentID" -Headers $Headers
    $delVerification = $null
    $delVerification = [pscustomobject]@{
        ReasonCode = $deleteStatus.data.children.data.collapsed_reason_code
        Body       = $deleteStatus.data.children.data.body
        Author     = $deleteStatus.data.children.data.author
    }
    $delVerification | fl
}
####################################################################################





