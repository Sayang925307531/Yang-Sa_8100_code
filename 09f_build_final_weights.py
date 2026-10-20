import sys, pandas as pd, numpy as np
SRC, OUT = (sys.argv[1], sys.argv[2])
f = pd.read_csv(SRC, dtype=str)
f['fy'] = f.fiscal_year.astype(int)
f['rcp'] = f.report_url.str.extract('rcpNo=(\\d+)')[0]
num = lambda s: pd.to_numeric(s, errors='coerce')
f['amt_krw'] = num(f.amount_raw) * num(f.unit_krw)
f['tot_krw'] = num(f.total_raw) * num(f.total_unit_krw)
f['cust'] = np.where(f.customer.str.contains('hynix'), 'h', 's')
rows = []

def add(code, fy, cust, w, src, alt=np.nan, alt_src='', flags='', resolution=''):
    r = f[(f.stock_code == code) & (f.fy == fy) & (f.cust == cust)].iloc[0]
    rows.append(dict(stock_code=code, company_name=r.company_name, fiscal_year=fy, customer=cust, weight=w, weight_source=src, weight_alt=alt, weight_alt_source=alt_src, customer_revenue_krw=r.amt_krw, total_revenue_krw=r.tot_krw, public_by_date=r.public_by_date, rcpNo=r.rcp, report_url=r.report_url, section_url=r.section_url, evidence_file=r.evidence_file, sha256=r.sha256, flags=flags, resolution_note=resolution))
amt = lambda code, fy, c: f[(f.stock_code == code) & (f.fy == fy) & (f.cust == c)].eval('amt_krw/tot_krw').iloc[0]
for fy in range(2020, 2025):
    for c in 'hs':
        add('005290', fy, c, amt('005290', fy, c), 'amount/consolidated revenue', flags='')
for fy in range(2020, 2025):
    for c in 'hs':
        add('222800', fy, c, amt('222800', fy, c), 'amount/consolidated revenue')
for fy in range(2020, 2024):
    for c in 'hs':
        add('036710', fy, c, amt('036710', fy, c), 'amount/consolidated revenue', flags='parent_overlap')
add('036710', 2024, 'h', amt('036710', 2024, 'h'), 'amount/consolidated revenue', flags='parent_overlap', resolution='海力士金额258,912,802千韩元与子公司Simmtech一致。')
add('036710', 2024, 's', amt('036710', 2024, 's'), 'amount/consolidated revenue', alt=419721148130 / 1302111614000, alt_src='子公司Simmtech披露的三星金额÷母公司合并收入', flags='parent_overlap;cross_issuer_discrepancy', resolution='母公司自身合并附注(4)主要客户列三星电子379,037,032千韩元；子公司年报列419,721,148千韩元。权重按发行人自身报告取值；差异原因原文未说明，另列alt供敏感性。')
add('039440', 2020, 'h', 0.1, 'reported pct (business section, consolidated)', alt=26752150 / 269101402, alt_src='진행기준 당기인식액÷合并收入', flags='rounded_pct', resolution='业务章节(5)주요 매출처（合并）：三星电子48%、三星显示13%、海力士10%、CSOT 5%；海力士进度收入9.94%与10%一致。')
add('039440', 2020, 's', 0.48, 'reported pct (business section, consolidated)', alt=141305884 / 269101402, alt_src='진행기준 당기인식액÷合并收入', flags='rounded_pct;source_discrepancy', resolution='主要客户附注只列“삼성전자 등”(集团合计,不可用)。业务章节明确三星电子48%；进度收入表三星电子141,305,884千韩元=52.5%。同表三星显示/海力士/CSOT均与业务章节比例一致，唯三星不一致，原因未披露。主值采用实名比例48%，52.5%作alt。')
add('039440', 2021, 'h', amt('039440', 2021, 'h'), 'amount/consolidated revenue', alt=0.13, alt_src='reported pct')
add('039440', 2021, 's', 0.41, 'reported pct (business section, consolidated)', alt=129699964 / 319513984, alt_src='진행기준 당기인식액÷合并收入', flags='rounded_pct', resolution='附注主要客户为“삼성전자 등”集团合计，不可用；业务章节明确三星电子41%、海力士13%、三星显示4%。')
add('039440', 2022, 'h', amt('039440', 2022, 'h'), 'amount/consolidated revenue', alt=0.12, alt_src='reported pct')
add('039440', 2022, 's', 0.39, 'reported pct (business section, consolidated)', alt=159218987 / 422418754, alt_src='진행기준 当期認識額÷合并收入（FY2023年报把该金额列为FY2022三星电子主要客户收入）', flags='rounded_pct', resolution='附注主要客户为集团合计；业务章节三星电子39%。FY2023年报比较期把159,218,987千韩元列为三星电子收入(37.7%)，作alt。')
for fy in (2023, 2024):
    for c in 'hs':
        add('039440', fy, c, amt('039440', fy, c), 'amount/consolidated revenue', resolution='合并附注主要客户实名分列三星电子与海力士；三星显示单列并排除。' + ('海力士5.2%已对照原文：附注当期16,673,796千韩元、上期48,771,154千韩元，属实。' if fy == 2023 and c == 'h' else ''))
for fy in range(2020, 2025):
    add('052900', fy, 's', amt('052900', fy, 's'), 'amount/consolidated revenue', resolution='海力士未披露（SK Broadband不是海力士），保持缺失。')
add('025560', 2020, 'h', amt('025560', 2020, 'h'), 'amount/consolidated revenue', alt=0.2648, alt_src='业务章节报告比例（与合并收入不同口径）', flags='segment_listing', resolution='合并附注(3)按部门列主要客户：ATE部门SK하이닉스10,441,129,250원；业务章节同额10,441百万원但比例26.48%，对应分母约394亿원，非合并收入415.6亿원。按定义用合并分母=25.12%。SMT部门未列海力士。')
for fy in (2021, 2022):
    add('025560', fy, 'h', amt('025560', fy, 'h'), 'amount/consolidated revenue', flags='segment_listing', resolution='合并附注按部门列客户，仅ATE部门列海力士；SMT部门列出的客户中无海力士。若SMT对海力士有少量销售则本值略低估（FY2023/24 SMT对海力士分别仅3.9亿/1.5亿원）。')
add('025560', 2023, 'h', amt('025560', 2023, 'h'), 'amount/consolidated revenue', resolution='ATE+SMT两部门海力士合计。')
add('025560', 2024, 'h', amt('025560', 2024, 'h'), 'amount/consolidated revenue', alt=0.1542, alt_src='业务章节报告比例（不同分母）', resolution='ATE+SMT合计4,211百万원，同额；报告比例15.42%分母不同，按合并分母=15.57%。')
add('080000', 2020, 's', amt('080000', 2020, 's'), 'amount/consolidated revenue', flags='small_weight', resolution='附注“공정장비 사업부 주요 외부고객”实名列三星电子(주)352,265千韩元，三星显示3,369,753千韩元单列并排除。合并收入101,854,315千韩元。FY2021年报比较期口径不同不影响原报可得值。')
add('212710', 2024, 'h', amt('212710', 2024, 'h'), 'amount/consolidated revenue (Korean legal entity)', alt=(7785345 + 4258852) / 41086620, alt_src='含SK HYNIX SEMICONDUCTOR CHINA（集团口径）', flags='legal_entity_only', resolution='业务章节10%以上客户表：주식회사 하이닉스7,785,345千韩元；SK HYNIX SEMICONDUCTOR CHINA 4,258,852千韩元另列。主值按韩国法人，集团口径29.3%作alt。2025-02-12上市，早期事件无股价。')
w = pd.DataFrame(rows)
assert not w.duplicated(['stock_code', 'fiscal_year', 'customer']).any()
assert w.weight.between(0, 1).all()
assert (pd.to_datetime(w.rcpNo.str[:8]) == pd.to_datetime(w.public_by_date)).all()
w['fiscal_end'] = w.fiscal_year.astype(str) + '-12-31'
w['approved'] = 1
w.to_csv(f'{OUT}/customer_weights_firm_year_customer_LONG.csv', index=False, encoding='utf-8-sig')
wide = w.pivot_table(index=['stock_code', 'company_name', 'fiscal_year', 'fiscal_end', 'public_by_date', 'rcpNo'], columns='customer', values=['weight', 'weight_alt'], aggfunc='first')
wide.columns = [f'{a}_{b}' for a, b in wide.columns]
wide = wide.rename(columns={'weight_h': 'w_h', 'weight_s': 'w_s', 'weight_alt_h': 'w_h_alt', 'weight_alt_s': 'w_s_alt'}).reset_index()
fl = w.groupby(['stock_code', 'fiscal_year']).flags.apply(lambda s: ';'.join(sorted({x for v in s for x in str(v).split(';') if x})))
wide = wide.merge(fl.rename('flags').reset_index(), on=['stock_code', 'fiscal_year'])
for c in ['w_h', 'w_s', 'w_h_alt', 'w_s_alt']:
    if c not in wide:
        wide[c] = np.nan
wide['both_known'] = wide[['w_h', 'w_s']].notna().all(axis=1).astype(int)
wide = wide[['stock_code', 'company_name', 'fiscal_year', 'fiscal_end', 'public_by_date', 'rcpNo', 'w_h', 'w_s', 'w_h_alt', 'w_s_alt', 'both_known', 'flags']]
wide.to_csv(f'{OUT}/customer_weights_firm_year_FINAL.csv', index=False, encoding='utf-8-sig')
b = f[f.interval_upper_exclusive.notna()][['stock_code', 'company_name', 'fiscal_year', 'customer', 'public_by_date', 'interval_upper_exclusive', 'interval_scope', 'report_url', 'evidence_file']]
b.to_csv(f'{OUT}/customer_weights_below10pct_bounds.csv', index=False, encoding='utf-8-sig')
import os
grid = os.path.join(os.path.dirname(SRC), 'DART_company_year_review_grid_118.csv')
g = pd.read_csv(grid, dtype=str)
cal = g[(pd.to_numeric(g.original_fiscal_year_filing_verified, errors='coerce') == 1) & g.public_by_date.notna()][['stock_code', 'company_name', 'fiscal_year', 'public_by_date', 'report_url']].copy()
cal['fiscal_year'] = cal.fiscal_year.astype(int)
cal.to_csv(f'{OUT}/annual_report_calendar_SY118.csv', index=False, encoding='utf-8-sig')
print(wide.round(4).to_string(index=False))
print('long rows', len(w), 'firm-years', len(wide), 'bounds rows', len(b))
