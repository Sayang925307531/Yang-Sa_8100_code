version 17.0

tempfile drops
import delimited using "$sample_drop", encoding("utf-8") stringcols(_all) clear
unab allv : _all
local first : word 1 of `allv'
if "`first'"!="repetition" rename `first' repetition
keep stock_code
assert regexm(stock_code,"^[0-9][0-9][0-9][0-9][0-9][0-9]$")
isid stock_code
assert _N==25
gen byte drop_rep5583=1
save `drops'

foreach panel in regression_panel weighted_panel {
    capture confirm file "$clean/`panel'.dta"
    if !_rc {
        use "$clean/`panel'.dta", clear
        capture confirm variable sample_rep5583
        if _rc save "$clean/`panel'_full.dta", replace
    }
    use "$clean/`panel'_full.dta", clear
    capture confirm variable sample_rep5583
    assert _rc!=0
    merge m:1 stock_code using `drops', keep(master match)
    if "`panel'"=="regression_panel" {
        assert _N==153*16
        preserve
            keep if _merge==3
            contract stock_code
            assert _N==25 & _freq==16
        restore
        preserve
            keep if _merge==3
            keep stock_code company_name event_id base_ok retail_ok eps_ok triple_ok d car02
            write_csv using "$audit/sample_rep5583_dropped_rows.csv", replace
        restore
    }
    drop if _merge==3
    drop _merge drop_rep5583
    gen byte sample_rep5583=1
    label variable sample_rep5583 "Analysis sample: drop 25 firms (random-25 draw 5583, seed820025)"
    if _N>0 isid firm_id event_id
    if "`panel'"=="regression_panel" assert _N==128*16
    save "$clean/`panel'.dta", replace
}
use "$clean/regression_panel.dta", clear
local n_dta = _N
export delimited using "$clean/regression_panel.csv", replace datafmt
preserve
    import delimited using "$clean/regression_panel.csv", clear varnames(1) stringcols(_all)
    assert _N == `n_dta'
restore
quietly count if base_ok
display "SAMPLE rep5583: rows=" _N "; M1 base_ok=" r(N)
