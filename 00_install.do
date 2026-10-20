version 17.0
foreach pkg in ftools reghdfe estout boottest {
    local cmd `pkg'
    if "`pkg'"=="estout" local cmd esttab
    capture which `cmd'
    if _rc ssc install `pkg'
}
which reghdfe
which boottest
