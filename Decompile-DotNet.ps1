<# ==============================================================================================
 
    Name : Decompile .Net code in Powershell (Decompile-DotNet.ps1)
    Description : Decompile code .Net with ILSpy
 
    Author : Pierre-Alexandre Braeken
    Date : 11 March 2015    
       
    The script browse a list of directory and decompile the .Net code file presents in the 
    assemblies there    
    
    You have to put the assemblies uses in the .Net assemblies for decompiled all the function 
    used in the .Net assemblies
    
    You get :
    
    * file (.CIL) with the Common Intermediate Language content
    * file (.ref) with the references used in the assemblies
    * file (.cs) with the decompiled .Net code 
    * All.txt file with the references used in all the found .Net assemblies
           
# ============================================================================================== #>

# ¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯
# Function Name 'Read-OpenFileDialog' - Open an open File Dialog box
# ________________________________________________________________________
Function Read-OpenFileDialog([string]$InitialDirectory, [switch]$AllowMultiSelect) {      
    [System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms") | Out-Null
    $openFileDialog = New-Object System.Windows.Forms.OpenFileDialog        
    $openFileDialog.ShowHelp = $True
    $openFileDialog.initialDirectory = $initialDirectory
    $openFileDialog.filter = "csv files (*.csv)|*.csv|All files (*.*)| *.*"
    $openFileDialog.FilterIndex = 1
    $openFileDialog.ShowDialog() | Out-Null
    return $openFileDialog.filename
}
# ¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯
# Function Name 'ListFile' - get path based on a CSV file
# ________________________________________________________________________
Function ListFile {	
    $fileOpen = Read-OpenFileDialog $scriptPath
    if($fileOpen -ne '') {	
		$colPath = Import-Csv $fileOpen
    }
    $colPath
}

# ¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯
# Function Name 'GetCodeNET' - get .net code from executables
# ________________________________________________________________________
Function GetCodeNET($fileToAnalyse) {    	
    $toAdd = @()    

    $assembly = $fileToAnalyse.FullName
    $codeCIL = "$scriptPath\temp\exe\" + $fileToAnalyse.Name + ".CIL"    
    $codeNet = "$scriptPath\temp\exe\" + $fileToAnalyse.Name + ".cs"        
    $codeRef = "$scriptPath\temp\exe\" + $fileToAnalyse.Name + ".ref"    
    
    $resolver  = New-Object Mono.Cecil.DefaultAssemblyResolver 
    $resolver.AddSearchDirectory("$scriptPath\dll");

    $parameters = New-Object Mono.Cecil.ReaderParameters
    $parameters.AssemblyResolver = $resolver

    $assemblyDefinition = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($assembly, $parameters);                   
  
    $context = New-Object ICSharpCode.Decompiler.DecompilerContext -ArgumentList $assemblyDefinition.MainModule    
    
    $textOutput = New-Object ICSharpCode.Decompiler.PlainTextOutput
    $decompilationOptions = New-Object ICSharpCode.ILSpy.DecompilationOptions
    $cSharpLanguage = New-Object ICSharpCode.ILSpy.CSharpLanguage     
    
    $loaded =[reflection.assembly]::LoadFile($assembly)
    $name = $loaded.ManifestModule
   
    $loaded.GetReferencedAssemblies() | % {                
        $fileToAnalyse.Name + ";" + $_.FullName + ";" + $_.Name | Out-File -append $references     
        $fileToAnalyse.Name + ";" + $_.FullName + ";" + $_.Name | Out-File -append $codeRef     
    }       
    foreach($typeDefinition in $assemblyDefinition.MainModule.Types){
        foreach($method in $typeDefinition.Methods) {   
            $method.Name | Out-File -append $codeCIL 
            $method.Body.Instructions | Out-File -append $codeCIL        
            try {     
                $cSharpLanguage.DecompileMethod($method,$textOutput,$decompilationOptions)                   
            }
            catch [exception] {    		   
               $_.Exception.InnerException | Out-File -append $errors     		   
    		}                          
        }           
    }    
    $textOutput.ToString() | Out-File -append $codeNet
}

$scriptPath = split-path -parent $MyInvocation.MyCommand.Definition
$scriptFile = $MyInvocation.MyCommand.Definition

Add-Type -Path "$scriptPath\ILSpy\Mono.Cecil.dll"
Add-Type -Path "$scriptPath\ILSpy\Mono.Cecil.Pdb.dll"
Add-Type -Path "$scriptPath\ILSpy\ICSharpCode.Decompiler.dll"
[void][System.Reflection.Assembly]::LoadFrom("$scriptPath\ILSpy\ILSpy.exe")   

$colPath = ListFile
$references = "$scriptPath\temp\exe\All.txt"
$errors = "$scriptPath\errors.txt"  

"File;ReferenceFullName;ReferenceName" | Out-File -append $references   
$arrayFileFiltered = @()

foreach ($strPath in $colPath){
    $path = $strPath.path
    $total = [System.IO.Directory]::GetFiles("$path", '*', 'AllDirectories').Count
    Write-Progress -Activity "Getting file structure" -status "Running..." -id 1 
    $filesPresent = Get-Childitem $path -Recurse | where {!$_.PSIsContainer} | Select-Object Name, Extension, Length, DirectoryName, LastWriteTime, FullName    
    foreach ($file in $filesPresent){                    
        Write-Progress -Activity "Decompile $file" -status "Running..." -id 1 
        GetCodeNET $file                          
    }    
}