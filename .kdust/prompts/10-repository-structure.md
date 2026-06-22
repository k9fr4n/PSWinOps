# REPOSITORY STRUCTURE

```
PSWinOps/
├── build.ps1
├── coverage.xml
├── en-US
│   └── about_PSWinOps.help.txt
├── output
│   └── PSWinOps
│       ├── PSWinOps.Format.ps1xml
│       ├── PSWinOps.psd1
│       └── PSWinOps.psm1
├── Private
│   ├── ConvertFrom-QUserIdleTime.ps1
│   ├── ConvertTo-ScheduledTaskResultMessage.ps1
│   ├── Invoke-NativeCommand.ps1
│   ├── Invoke-RemoteOrLocal.ps1
│   └── Test-IsAdministrator.ps1
├── PSWinOps.Format.ps1xml
├── PSWinOps.psd1
├── PSWinOps.psm1
├── PSWinOpsHealthStatus.ps1
├── Public
│   ├── activedirectory
│   ├── healthcheck
│   ├── network
│   ├── ntp
│   ├── proxy
│   ├── rdp
│   ├── system
│   └── utils
├── readme.md
└── Tests
    ├── Private
    └── Public
        ├── activedirectory
        ├── healthcheck
        ├── network
        ├── ntp
        ├── proxy
        ├── rdp
        ├── system
        └── utils
```

> NOTE: The canonical, exhaustive file listing lives in the live repository.
> This file captures the top-level layout the prompt relies on; the agent
> reads the real tree from disk for the authoritative state.
