from pathlib import Path
from datetime import date, datetime, timezone
import csv, hashlib, json, shutil
import pandas as pd
ROOT = Path('D:/ANU/s4/8100/ass')
SY = ROOT / 'SY'
OUT = SY / 'data/customer_weights'
for folder in ['candidate', 'audit', 'evidence', 'browser_review', 'code']:
    (OUT / folder).mkdir(parents=True, exist_ok=True)
source = ROOT / 'data/02_customer_relationships/wrds_factset_core_target_relationships_2021-2025_raw_20261010.csv'
panel_path = SY / 'data/clean/regression_panel.dta'
panel = pd.read_stata(panel_path, convert_categoricals=False)
assert not panel.duplicated(['firm_id', 'event_id']).any()
master = panel[['company_id', 'stock_code', 'company_name', 'firm_id', 'role']].drop_duplicates()
assert master.company_id.is_unique and master.stock_code.is_unique
master['in_m1'] = master.stock_code.isin(panel.loc[panel.base_ok.eq(1), 'stock_code']).astype(int)
master.to_csv(OUT / 'audit/SY_company_scope.csv', index=False, encoding='utf-8-sig')
scope = master[master.in_m1.eq(1)].copy()
assert len(scope) == 118
raw = pd.read_csv(source, dtype=str).fillna('')
raw['source_row_number'] = range(2, len(raw) + 2)
rel = raw[(raw.rel_type == 'CUSTOMER') & raw.target_company_id.isin(['1835724', '1401901'])]
rel = rel.merge(scope, left_on='source_company_id', right_on='company_id', how='inner', validate='many_to_one')
rel['candidate_id'] = rel.source_row_number.map(lambda x: f'FS_{x:06d}')
rel['revenue_pct_raw'] = pd.to_numeric(rel.revenue_percent, errors='coerce')
rel['customer'] = rel.target_company_id.map({'1835724': 'Samsung Electronics', '1401901': 'SK hynix'})
rel.to_csv(OUT / 'candidate/SY_M1_all_customer_records.csv', index=False, encoding='utf-8-sig')
c = rel[rel.revenue_pct_raw.notna()].copy()
c['candidate_share_pct_assumed'] = c.revenue_pct_raw / 100
c['unit_verified'] = 0
c['estimated_flag'] = c.percent_estimated.eq('Y').astype(int)
c['record_start'] = c.start_
c['record_end'] = c.end_
c['interval_valid'] = c.apply(lambda r: bool(r.record_start and r.record_end and (r.record_start < r.record_end)), axis=1).astype(int)
c['source_subsidiary_flag'] = c.source_company_subsidiaries.ne('').astype(int)
c['target_subsidiary_flag'] = c.target_company_subsidiaries.ne('').astype(int)
c['display_scope_flag'] = c[['target_name', 'target_company_subsidiaries']].agg(' '.join, axis=1).str.contains('Samsung\\s*Display|삼성디스플레이', case=False, regex=True).astype(int)
c['scope_review_required'] = (c.source_subsidiary_flag + c.target_subsidiary_flag > 0).astype(int)
c['same_period_rows'] = c.groupby(['stock_code', 'target_company_id', 'record_start', 'record_end']).candidate_id.transform('size')
c['same_period_value_count'] = c.groupby(['stock_code', 'target_company_id', 'record_start', 'record_end']).revenue_pct_raw.transform('nunique')
c['exact_duplicate_flag'] = c.duplicated(subset=[x for x in raw.columns if x != 'source_row_number'], keep=False).astype(int)
c['overlap_rows'] = 0
overlaps = []
for _, group in c.groupby(['stock_code', 'target_company_id']):
    rows = list(group.itertuples())
    for i, a in enumerate(rows):
        for b in rows[i + 1:]:
            if a.interval_valid and b.interval_valid and (max(a.record_start, b.record_start) < min(a.record_end, b.record_end)):
                c.loc[c.candidate_id.isin([a.candidate_id, b.candidate_id]), 'overlap_rows'] += 1
                overlaps.append({'candidate_a': a.candidate_id, 'candidate_b': b.candidate_id, 'stock_code': a.stock_code, 'customer': a.customer, 'overlap_start': max(a.record_start, b.record_start), 'overlap_end_exclusive': min(a.record_end, b.record_end), 'same_value': int(a.revenue_pct_raw == b.revenue_pct_raw), 'scope_a': a.target_company_subsidiaries, 'scope_b': b.target_company_subsidiaries})
c['fiscal_end_verified'] = ''
c['public_by_date_verified'] = ''
c['availability_verified'] = 0
c['approved'] = 0
c['status'] = 'UNVERIFIED_FACTSET_CANDIDATE'
c['source_csv'] = str(source)
c['source_sha256'] = hashlib.sha256(source.read_bytes()).hexdigest()
cols = ['candidate_id', 'stock_code', 'company_name', 'customer', 'revenue_pct_raw', 'candidate_share_pct_assumed', 'percent_estimated', 'record_start', 'record_end', 'interval_valid', 'target_company_subsidiaries', 'source_company_subsidiaries', 'display_scope_flag', 'scope_review_required', 'same_period_rows', 'same_period_value_count', 'overlap_rows', 'exact_duplicate_flag', 'fiscal_end_verified', 'public_by_date_verified', 'availability_verified', 'unit_verified', 'approved', 'status']
c[cols + [x for x in c if x not in cols]].to_csv(OUT / 'candidate/FactSet_candidates_UNVERIFIED.csv', index=False, encoding='utf-8-sig')
pd.DataFrame(overlaps, columns=['candidate_a', 'candidate_b', 'stock_code', 'customer', 'overlap_start', 'overlap_end_exclusive', 'same_value', 'scope_a', 'scope_b']).to_csv(OUT / 'audit/overlapping_records.csv', index=False, encoding='utf-8-sig')
events = panel[panel.base_ok.eq(1)][['stock_code', 'firm_id', 'event_id', 'ref_date', 'event_date']].copy()
events['ref_date_text'] = events.ref_date.dt.strftime('%Y-%m-%d')
matched = events.merge(c[cols], on='stock_code', how='inner', validate='many_to_many')
matched = matched[(matched.interval_valid == 1) & (matched.record_start < matched.ref_date_text) & (matched.ref_date_text < matched.record_end)].copy()
matched['interval_proxy_only'] = 1
matched['formal_weight_eligible'] = 0
matched.to_csv(OUT / 'candidate/event_candidate_links_INTERVAL_ONLY.csv', index=False, encoding='utf-8-sig', date_format='%Y-%m-%d')
assert not matched.duplicated(['firm_id', 'event_id', 'candidate_id']).any()
matched_count = matched.groupby('stock_code').event_id.nunique()
items = []
for r in scope.sort_values('stock_code').itertuples():
    subset = c[c.stock_code == r.stock_code]
    both = int(subset.target_company_id.nunique() == 2)
    items.append({'stock_code': r.stock_code, 'company_name': r.company_name, 'company_id': r.company_id, 'factset_rows': len(subset), 'distinct_customers_ever': subset.target_company_id.nunique(), 'both_customers_ever': both, 'interval_candidate_events': int(matched_count.get(r.stock_code, 0)), 'display_rows': int(subset.display_scope_flag.sum()), 'subsidiary_scope_rows': int(subset.scope_review_required.sum()), 'invalid_interval_rows': int((1 - subset.interval_valid).sum()), 'priority': 1 if both else 2 if len(subset) else 3, 'review_status': 'NOT_REVIEWED_IN_THIS_BATCH'})
queue = pd.DataFrame(items).sort_values(['priority', 'stock_code'])
queue.to_csv(OUT / 'candidate/DART_review_queue_118.csv', index=False, encoding='utf-8-sig')
queue[queue.factset_rows > 0].to_csv(OUT / 'candidate/company_candidate_summary_19.csv', index=False, encoding='utf-8-sig')
dta = c[cols].copy()
dta = dta.rename(columns={'candidate_share_pct_assumed': 'share_assumed', 'target_company_subsidiaries': 'target_subsidiaries', 'source_company_subsidiaries': 'source_subsidiaries'})
dta.to_stata(OUT / 'candidate/factset_candidates_unverified.dta', write_index=False, version=118)
previous = ROOT / 'data/03_customer_sales_weights/verification_20261010/verified_customer_weights_audit.csv'
verified = pd.read_csv(previous, dtype={'stock_code': str})
verified = verified[verified.stock_code.isin(scope.stock_code)]
verified['provenance'] = 'PREVIOUS_SOURCE_VERIFICATION_20261010; browser recheck separately logged'
verified.to_csv(OUT / 'evidence/existing_verified_weights_4.csv', index=False, encoding='utf-8-sig')
review = OUT / 'browser_review/browser_review_register.csv'
if not review.exists():
    pd.DataFrame(columns=['stock_code', 'fiscal_year', 'customer', 'report_url', 'browser_reviewed', 'review_result', 'public_by_date', 'evidence_file', 'sha256', 'note']).to_csv(review, index=False, encoding='utf-8-sig')
manifest = {'created_utc': datetime.now(timezone.utc).isoformat(), 'scope': 'SY baseline eligible118 companies;128-company panel index separately retained', 'inputs': [{'path': str(p), 'sha256': hashlib.sha256(p.read_bytes()).hexdigest()} for p in [source, panel_path, previous]], 'counts': {'scope_companies': len(scope), 'relation_rows': len(rel), 'candidate_rows': len(c), 'candidate_companies': c.stock_code.nunique(), 'both_ever': int(queue.both_customers_ever.sum()), 'without_factset_value': int(queue.factset_rows.eq(0).sum()), 'display_rows': int(c.display_scope_flag.sum()), 'scope_review_rows': int(c.scope_review_required.sum()), 'invalid_interval_rows': int(c.interval_valid.eq(0).sum()), 'overlap_pairs': len(overlaps), 'event_candidate_rows': len(matched), 'candidate_approved': 0}, 'rules': {'start_is_publication_date': False, 'unit_conversion': 'raw numeric /100 is provisional percent interpretation; unit_verified=0', 'zero_fill': False, 'aggregate_overlapping_rows': False, 'formal_candidate_use': False}}
(OUT / 'audit/build_manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')
doc = '# SY客户销售权重：第1步候选整理\n\n本轮范围：SY的118家M1公司。SY全部128家公司索引另存，未纳入M1的公司未被误称已核验。\n\n## 看哪些文件\n- candidate/company_candidate_summary_19.csv：19家有比例线索的公司概览。\n- candidate/FactSet_candidates_UNVERIFIED.csv：逐条原始记录与问题标记，全部approved=0。\n- candidate/DART_review_queue_118.csv：完整核验队列，优先两客户均有历史数值的6家，再有单客户数值的13家，再无数值的99家；同级按证券代码，不按回归P值。\n- candidate/event_candidate_links_INTERVAL_ONLY.csv：只按start_严格早于参考日且参考日在有效区间内初筛的候选链接。每行仍未核验、formal_weight_eligible=0；不能直接输入回归。\n- candidate/factset_candidates_unverified.dta：Stata版候选表，尚非分析权重。\n- audit/overlapping_records.csv：同公司/目标客户有重叠区间的行对，不相加、不任取最新、不取平均。\n- evidence/existing_verified_weights_4.csv：此前4条已核验年度事实，独立保留；不是本轮新增批准。\n- browser_review/browser_review_register.csv：DART浏览器核验进度，逐报告/客户登记。\n\n## 关键字段与规则\ncandidate_id由来源CSV行号生成；id为FactSet关系ID。revenue_pct_raw保持原数值，candidate_share_pct_assumed=/100只是百分数单位假设，unit_verified=0。\nrecord_start/record_end原样保存，4000-01-01结束哨兵不转成缺失。零长度区间标记无效且不用于事件初筛，但源记录保留。\nstart_不直接作为最早可得日；public_by_date_verified与fiscal_end_verified等待报告证据，禁止从start_年份倒推财年。\ndisplay_scope_flag指出三星显示等范围问题；target/source subsidiary字段保留。附属实体可能是合法合并披露，但不自动符合研究定义的三星电子/海力士口径，需要核对原文。\n两种比例曾出现不等于同一年度可用，不等于单家公司两客户模型可估。\n匿名客户不映射；未提及不自动记低于10%；缺失不填0。所有新FactSet候选保持未批准。\n\n## 后续核验\n浏览器逐条打开DART原文；核对财年、客户名称、分子分母、金额单位、合并范围、申报/更正版本及当时公开日期。保存可见原文摘录/原文证据和SHA，再登记结论。正式权重需要独立审批记录，不能只靠FactSet区间匹配。\n\n源数据、SY模型和当前输入审核表未被覆盖。代码位于SY/code/09a_customer_weight_candidates.py，并在本目录code下保存副本。运行manifest记录源文件SHA及条数。\n'
(OUT / 'README_第1步候选与核验口径.md').write_text(doc, encoding='utf-8')
shutil.copyfile(Path(__file__), OUT / 'code' / Path(__file__).name)
assert len(c) == 149 and c.stock_code.nunique() == 19 and (int(queue.both_customers_ever.sum()) == 6)
assert c.approved.eq(0).all() and (not c.candidate_id.duplicated().any())
print(json.dumps(manifest['counts'], ensure_ascii=False, indent=2))
print(queue[queue.priority == 1][['stock_code', 'company_name', 'factset_rows', 'interval_candidate_events']].to_string(index=False))
