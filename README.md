# SEMI FUNCTIONAL STATE!!!! 

Import module with the PSM1 was having issues with PSD1

# BitbucketPS

BitbucketPS is a Windows PowerShell module to interact with [Atlassian Bitbucket](https://www.atlassian.com/software/bitbucket) via a REST API, while maintaining a consistent PowerShell look and feel.


## Requirements

This module has a hard dependency on PowerShell 3.0.  I have no plans to release a version compatible with PowerShell 2, as I rely heavily on several cmdlets and features added in version 3.0.


## Getting Started

Before using BitbucketPS, you'll need to define your Bitbucket server URL.  You will only need to do this once:

```powershell
Set-BBConfigServer "https://bitbucket.example.com"
```

To use BitbucketPS:

```powershell
Import-Module BitbucketPS
New-BBSession -Credential (Get-Credential YourUserName)
```

## Contact

Feel free to comment on this project here on GitHub using the issues or discussion pages.  You can also check out [my blog](http://beaudry.io) or catch me on [reddit](https://www.reddit.com/u/crossbeau).

*Note:* As with all community PowerShell modules and code, you use BitbucketPS at your own risk.  I am not responsible if your bitbucket instance causes a fire in your datacenter (literal or otherwise).
