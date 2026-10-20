version 17.0
set more off
set varabbrev off
set seed 810017
set type double

global root "D:/ANU/s4/8100/ass/SY"
global rawroot "D:/ANU/s4/8100/ass"
global code "$root/code"
global raw  "$rawroot/data"
global out  "$root/data"
global tmp  "$out/intermediate"
global clean "$out/clean"
global results "$root/results"
global logs "$results/logs"
global audit "$results/audit"
global tables "$results/tables"
global sample_drop "$out/sample_selection/removed_firms_rep5583.csv"
foreach d in out tmp clean results logs audit tables {
    capture mkdir "${`d'}"
}

global strict_review 0
global min_est 120
global min_pre 44
global min_base 12
global min_brokers 10
global forecast_age 120
global bootstrap_reps 9999

global pool "$raw/01_company_identity/working_pool_153_20261010/working_pool_153_identifiers_BRIEF_DERIVED.csv"
global prices "$raw/04_korea_daily_prices/derived_pool_153_20261010/compustat_working_pool_153_daily_compact_DERIVED.csv"
global links "$raw/02_customer_relationships/wrds_factset_core_target_relationships_2021-2025_raw_20261010.csv"
global krx_new "$raw/05_krx_retail_trading/native_english_portal/raw"
global krx_old "$raw/05_krx_retail_trading/imported_legacy60_20260917/raw"
global ibes "$raw/06_ibes_nvidia_eps"
global nvda "$raw/07_nvidia_price_splits/wrds_compustat_nvda_daily_prices_2021-2025_raw_20261010.csv"
global sox "$raw/08_sox_index/acquisition_20261010T061501Z_6fc6b3dd/raw/fred_NASDAQSOX_2021_2025.csv"

capture program drop write_csv
program define write_csv
    version 17.0
    syntax using/ [, REPLACE]
    if _N>0 {
        export delimited using "`using'", `replace'
    }
    else {
        unab columns : _all
        local header : subinstr local columns " " ",", all
        tempname handle
        file open `handle' using "`using'", write text `replace'
        file write `handle' "`header'" _n
        file close `handle'
    }
end
