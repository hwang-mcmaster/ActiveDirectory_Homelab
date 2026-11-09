@{
    RootModule = 'LabLifecycle.psm1'
    ModuleVersion = '1.0.0'
    GUID = '617d0c85-55fe-4ba7-b571-8eb523731009'
    Author = 'Sysadmin Lab Contributors'
    Description = 'Scoped, plan-first AD lifecycle automation for an isolated lab.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @('Read-LabConfig','Read-LifecycleCsv','Invoke-LabLifecycle')
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
}
