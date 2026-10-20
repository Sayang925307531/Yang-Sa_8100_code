tempfile stockret sox usdays aligned
import delimited "$prices", clear varnames(1) stringcols(_all) encoding("utf-8")
replace gvkey=string(real(gvkey),"%06.0f")
gen double date=daily(datadate,"YMD")
format date %tdCCYY-NN-DD
foreach v in prccd ajexdi cshoc cshtrd prcstd qunit exchg {
    destring `v', replace
}
isid gvkey iid date
merge m:1 gvkey iid using "$clean/company_master.dta", generate(id_merge)
tabulate id_merge
assert id_merge!=1
keep if id_merge==3
drop id_merge
merge m:1 date using "$clean/kr_calendar.dta", keepusing(t) generate(cal_merge)
tabulate cal_merge
preserve
    keep if cal_merge==1
    write_csv using "$audit/price_rows_outside_calendar.csv", replace
restore
keep if cal_merge==3
drop cal_merge
assert curcdd=="KRW"
assert qunit==1 if !missing(qunit)
gen byte valid_price=inlist(prcstd,3,10) & prccd>0 & ajexdi>0 & !missing(prccd,ajexdi)
gen double price_adj=prccd/ajexdi if valid_price
sort firm_id t
by firm_id: gen double ret=price_adj/price_adj[_n-1]-1 if t==t[_n-1]+1 & valid_price & valid_price[_n-1]
assert ret>-1 if !missing(ret)
gen double market_cap=prccd*cshoc if valid_price & cshoc>0 & !missing(cshoc)
gen double turnover=cshtrd/cshoc if cshtrd>=0 & cshoc>0 & !missing(cshtrd,cshoc)
gen byte market_ok=inlist(exchg,248,298)
label variable ret "Adjacent KR session split-adjusted price return; decimal"
label variable market_cap "Issue-level raw price x actual shares; KRW"
label variable turnover "Actual traded shares / actual outstanding shares; ratio"
keep firm_id stock_code company_id gvkey iid company_name role identity_verified include_candidate date t ret price_adj prccd ajexdi cshoc cshtrd prcstd valid_price market_cap turnover market_ok
isid firm_id date
save `stockret'

import delimited "$sox", clear varnames(1) stringcols(_all) encoding("utf-8")
gen double us_date=daily(observation_date,"YMD")
gen double sox_close=real(nasdaqsox)
keep us_date sox_close
isid us_date
save `sox'
import delimited "$nvda", clear varnames(1) stringcols(_all) encoding("utf-8")
gen double us_date=daily(datadate,"YMD")
destring prccd ajexdi prcstd, replace
assert tic=="NVDA" & curcdd=="USD"
assert inlist(prcstd,3,10) & prccd>0 & ajexdi>0 & !missing(prccd,ajexdi)
gen double nvda_price_adj=prccd/ajexdi
keep us_date prccd ajexdi nvda_price_adj
isid us_date
merge 1:1 us_date using `sox', generate(sox_merge)
tabulate sox_merge
drop if sox_merge==2
drop sox_merge
sort us_date
format us_date %tdCCYY-NN-DD
save "$clean/us_daily.dta", replace
save `usdays'

use "$clean/kr_calendar.dta", clear
cross using `usdays'
keep if us_date<date
by date (us_date), sort: keep if _n==_N
isid date
sort t
gen double sox_ret=sox_close/sox_close[_n-1]-1 if t==t[_n-1]+1
keep date t us_date sox_close sox_ret
label variable sox_ret "SOX price-index return between successive KR-session information sets"
save "$clean/sox_kr_aligned.dta", replace
save `aligned'

use `stockret', clear
merge m:1 date using `aligned', keepusing(us_date sox_close sox_ret) generate(sox_merge)
tabulate sox_merge
drop if sox_merge==2
merge 1:1 firm_id date using "$clean/retail_daily.dta", keepusing(retail_buy retail_sell total_value retail_share retail_valid) generate(retail_merge)
tabulate retail_merge
drop if retail_merge==2
replace retail_valid=0 if missing(retail_valid)
isid firm_id date
compress
save "$clean/daily_panel.dta", replace
