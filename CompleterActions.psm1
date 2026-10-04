$sourceRoot = Join-Path -Path $PSScriptRoot -ChildPath 'src'
$functionFolders = @('Private', 'Public')

ForEach ($folder in $functionFolders)
{
    $folderPath = Join-Path -Path $sourceRoot -ChildPath $folder
    If (Test-Path -Path $folderPath)
    {
        Write-Verbose -Message "Importing from $folder"
        $functions = Get-ChildItem -Path $folderPath -Filter '*.ps1' | Sort-Object -Property Name
        ForEach ($function in $functions)
        {
            Write-Verbose -Message "  Importing $($function.BaseName)"
            . $($function.FullName)
        }
    }
}

. (Join-Path -Path $sourceRoot -ChildPath 'Bootstrap.ps1')

$publicFunctions = Get-ChildItem -Path (Join-Path -Path $sourceRoot -ChildPath 'Public') -Filter '*.ps1' |
    Sort-Object -Property BaseName |
    Select-Object -ExpandProperty BaseName

Export-ModuleMember -Function $publicFunctions
