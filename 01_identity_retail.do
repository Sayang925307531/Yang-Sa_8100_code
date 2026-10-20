tempfile review master longretail
import delimited "$code/inputs/identity_review.csv", clear varnames(1) stringcols(_all) encoding("utf-8")
destring identity_verified include_candidate, replace
isid stock_code
save `review'
import delimited "$pool", clear varnames(1) stringcols(_all) encoding("utf-8")
rename candidate_six_digit_security_cod stock_code
rename compustat_name company_name
keep company_id stock_code company_name gvkey iid role identity_match_status
replace gvkey=string(real(gvkey),"%06.0f")
assert regexm(stock_code,"^[0-9][0-9][0-9][0-9][0-9][0-9]$")
assert identity_match_status=="ONE_TO_ONE_OBSERVED"
isid stock_code
isid company_id
isid gvkey iid
egen long firm_id=group(company_id)
merge 1:1 stock_code using `review', generate(review_merge)
assert review_merge==3
drop review_merge
assert inlist(identity_verified,0,1) & inlist(include_candidate,0,1)
label variable identity_verified "Historical identity and sample eligibility manually reviewed"
label variable firm_id "Numeric ID within this frozen candidate pool"
save "$clean/company_master.dta", replace
save `master'

clear
save `longretail', emptyok
tempname fh
postfile `fh' str6 stock_code str4 side str244 source_file long rows using "$audit/krx_file_inventory.dta", replace
foreach folder in "$krx_old" "$krx_new" {
    local files : dir "`folder'" files "*.csv"
    foreach f of local files {
        local code ""
        local side ""
        if regexm(strlower("`f'"),"^([0-9]+)_[0-9]+_[0-9]+_(buy|sell)_krw[.]csv$") {
            local code=regexs(1)
            local side=regexs(2)
        }
        if regexm("`f'","^krx12009_([0-9]+)_daily_(buy|sell)_value_") {
            local code=regexs(1)
            local side=regexs(2)
        }
        if "`code'"=="" {
            display as error "Unrecognised raw filename: `f'"
            exit 459
        }
        import delimited "`folder'/`f'", clear varnames(nonames) stringcols(_all) encoding("utf-8")
        assert c(k)==6
        assert v1[1]=="Date" & v4[1]=="Individuals" & v6[1]=="Total"
        drop in 1
        rename (v1 v2 v3 v4 v5 v6) (date_text institution othercorp retail foreign total)
        gen double date=daily(date_text,"YMD")
        assert !missing(date)
        format date %tdCCYY-NN-DD
        foreach v in institution othercorp retail foreign total {
            destring `v', replace ignore(",")
            assert `v'>=0 if !missing(`v')
        }
        assert institution+othercorp+retail+foreign==total if !missing(institution,othercorp,retail,foreign,total)
        gen str6 stock_code="`code'"
        gen byte side=cond("`side'"=="buy",1,2)
        gen str244 source_file="`folder'/`f'"
        isid stock_code date side
        post `fh' ("`code'") ("`side'") (source_file[1]) (_N)
        keep stock_code date side retail total source_file
        append using `longretail'
        save `longretail', replace
    }
}
postclose `fh'

sort stock_code date side source_file
by stock_code date side: gen int n_sources=_N
by stock_code date side: gen byte conflict=(retail!=retail[1] | total!=total[1])
preserve
    keep if n_sources>1
    write_csv using "$audit/krx_overlap_rows.csv", replace
restore
assert conflict==0
by stock_code date side: keep if _n==1
drop conflict
reshape wide retail total source_file n_sources, i(stock_code date) j(side)
rename (retail1 retail2 total1 total2) (retail_buy retail_sell total_buy total_sell)
gen byte totals_agree=total_buy==total_sell if !missing(total_buy,total_sell)
assert totals_agree==1 if !missing(totals_agree)
gen double total_value=total_buy if totals_agree==1
gen byte retail_valid=!missing(retail_buy,retail_sell,total_value) & total_value>0
gen double retail_share=(retail_buy+retail_sell)/(2*total_value) if retail_valid
assert inrange(retail_share,0,1) if retail_valid
label variable retail_share "Individual buy+sell / (2 x one-sided total); ratio"
label variable total_value "One-sided trading value in KRW; buy/sell totals verified"
isid stock_code date
save "$clean/krx_all_downloaded.dta", replace

preserve
    keep if stock_code=="005930" & total_value>0 & !missing(total_value)
    keep date
    isid date
    sort date
    gen int t=_n
    gen int year=year(date)
    forvalues y=2021/2025 {
        count if year==`y'
        assert inrange(r(N),230,255)
    }
    label variable t "KR trading-session index derived from Samsung positive-volume dates"
    save "$clean/kr_calendar.dta", replace
    write_csv using "$audit/kr_calendar_review.csv", replace
restore
merge m:1 stock_code using `master', generate(master_merge)
tabulate master_merge
preserve
    keep if master_merge!=3
    write_csv using "$audit/krx_outside_current_pool.csv", replace
restore
keep if master_merge==3
drop master_merge
isid firm_id date
compress
save "$clean/retail_daily.dta", replace
preserve
    gen int year=year(date)
    collapse (count) downloaded_days=date (sum) valid_retail_days=retail_valid, by(stock_code year)
    write_csv using "$audit/retail_year_coverage.csv", replace
restore
