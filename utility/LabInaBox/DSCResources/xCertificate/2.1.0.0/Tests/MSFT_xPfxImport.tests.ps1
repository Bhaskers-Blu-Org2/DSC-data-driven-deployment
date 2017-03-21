<#
.Summary
    Tests for xPfxImport
#>


$moduleName = ($PSCommandPath | Split-Path -Leaf) -replace '\..*$',''
Import-Module ($PSScriptRoot | Split-Path -Parent | Join-Path -ChildPath DSCResources | Join-Path -ChildPath $moduleName | Join-Path -ChildPath "$moduleName.psm1") -DisableNameChecking -Force

InModuleScope $moduleName {
    $invalidThumbprint = 'Zebra'
    $validThumbprint = (
        [System.AppDomain]::CurrentDomain.GetAssemblies().GetTypes() | Where-Object {
            $_.BaseType.BaseType -eq [System.Security.Cryptography.HashAlgorithm] -and
            ($_.Name -cmatch 'Managed$' -or $_.Name -cmatch 'Provider$')
        } | Select-Object -First 1 | ForEach-Object { 
            (New-Object $_).ComputeHash([String]::Empty) | ForEach-Object {
                '{0:x2}' -f $_
            }
        }
    ) -join ''

    $testFile = 'test.pfx'

    $invalidPath = 'TestDrive:'
    $validPath = "TestDrive:\$testFile"
    $validCertPath = "Cert:\LocalMachine\My"

    $PresentParams = @{
        Thumbprint = $validThumbprint
        Path = $validPath
        Ensure = 'Present'
        Location = 'LocalMachine'
        Store = 'My'
    }

    $AbsentParams = @{
        Thumbprint = $validThumbprint
        Path = $validPath
        Ensure = 'Absent'
        Location = 'LocalMachine'
        Store = 'My'
    }
    
    Describe 'Validate-PfxPath' {

        $null | Set-Content -Path $validPath

        Context 'a single existing file by parameter' {
            $result = Validate-PfxPath -Path $validPath
            It 'should return true' {
                ($result -is [bool]) | Should Be $true
                $result | Should Be $true
            }
        }
        Context 'a single missing file by parameter' {
            It 'should throw an exception' {
                # directories are not valid
                { Validate-PfxPath -Path $invalidPath } | Should Throw
            }
        }
        Context 'a single missing file by parameter with -Quiet' {
            $result = Validate-PfxPath -Path $invalidPath -Quiet
            It 'should return false' {
                ($result -is [bool]) | Should Be $true
                $result | Should Be $false
            }
        }
        Context 'a single existing file by pipeline' {
            $result = $validPath | Validate-PfxPath
            It 'should return true' {
                ($result -is [bool]) | Should Be $true
                $result | Should Be $true
            }
        }
        Context 'a single missing file by pipeline' {
            It 'should throw an exception' {
                # directories are not valid
                { $invalidPath | Validate-PfxPath } | Should Throw
            }
        }
        Context 'a single missing file by pipeline with -Quiet' {
            $result =  $invalidPath | Validate-PfxPath -Quiet
            It 'should return false' {
                ($result -is [bool]) | Should Be $true
                $result | Should Be $false
            }
        }
    }
    Describe 'Validate-Thumbprint' {

        Context 'a single valid thumbrpint by parameter' {
            $result = Validate-Thumbprint -Thumbprint $validThumbprint
            It 'should return true' {
                ($result -is [bool]) | Should Be $true
                $result | Should Be $true
            }
        }
        Context 'a single invalid thumbprint by parameter' {
            It 'should throw an exception' {
                # directories are not valid
                { Validate-Thumbprint -Thumbprint $invalidThumbprint } | Should Throw
            }
        }
        Context 'a single invalid thumbprint by parameter with -Quiet' {
            $result = Validate-Thumbprint $invalidThumbprint -Quiet
            It 'should return false' {
                ($result -is [bool]) | Should Be $true
                $result | Should Be $false
            }
        }
        Context 'a single valid thumbprint by pipeline' {
            $result = $validThumbprint | Validate-Thumbprint
            It 'should return true' {
                ($result -is [bool]) | Should Be $true
                $result | Should Be $true
            }
        }
        Context 'a single invalid thumborint by pipeline' {
            It 'should throw an exception' {
                # directories are not valid
                { $invalidThumbprint | Validate-Thumbprint } | Should Throw
            }
        }
        Context 'a single invalid thumbprint by pipeline with -Quiet' {
            $result =  $invalidThumbprint | Validate-Thumbprint -Quiet
            It 'should return false' {
                ($result -is [bool]) | Should Be $true
                $result | Should Be $false
            }
        }
    }
    Describe 'Get-TargetResource' {
        $null | Set-Content -Path $validPath

        $result = Get-TargetResource @PresentParams
        It 'should return a hashtable' {
            ($result -is [hashtable]) | Should Be $true
        }
        It 'should contain the input values' {
            $result.Thumbprint | Should BeExactly $validThumbprint
            $result.Path | Should BeExactly $validPath
        }
    }
    Describe 'Test-TargetResource' {
        $null | Set-Content -Path $validPath

        It 'should return a bool' {
            ((Test-TargetResource @PresentParams) -is [bool]) | Should Be $true
        }
        It 'Fails when valid path + thumbprint and Ensure is Absent' {
            Mock Get-TargetResource { 
                return @{
                    Thumbprint = $validThumbprint
                    Path = $validPath
                    Ensure = 'Absent'
                }
            }
        
        Test-TargetResource @PresentParams | Should Be $false
        }
        It 'Success when valid path + thumbprint and Ensure is Present' {
            Mock Get-TargetResource { 
                return @{
                    Thumbprint = $validThumbprint
                    Path = $validPath
                    Ensure = 'Present'
                }
            }
        
            Test-TargetResource @PresentParams | Should Be $true
        }
    }
    Describe 'Set-TargetResource' {
        $null | Set-Content -Path $validPath
        
        Mock Import-PfxCertificate {} -Verifiable

        Set-TargetResource @PresentParams

        It 'calls Import-PfxCertificate' {
            Assert-VerifiableMocks
        }
        It 'uses the parameters supplied' {
            Assert-MockCalled Import-PfxCertificate -Exactly -Times 1 -ParameterFilter {
                $CertStoreLocation -eq $validCertPath -and
                $FilePath -eq $validPath -and
                $Exportable -eq $false -and
                $Password -eq $null
            }
        }
        It 'calls Get-ChildItem' {
            Mock Get-ChildItem {} -Verifiable
            Set-TargetResource @AbsentParams
            Assert-MockCalled Get-ChildItem -Scope It
        }
    }
}