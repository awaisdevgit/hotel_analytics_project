"""Loads raw source and executes SQL transformations. Requires a local MySQL server.
Uses getpass so credentials are not embedded in source code. Rebuild is explicit.
"""
from pathlib import Path
import argparse,getpass,json,hashlib
import pandas as pd
from sqlalchemy import create_engine,text
from sqlalchemy.engine import URL

def execute_file(conn,path):
    sql='\n'.join(line for line in Path(path).read_text().splitlines() if not line.lstrip().startswith('--'))
    for statement in sql.split(';'):
        if statement.strip():conn.execute(text(statement))

def main():
    p=argparse.ArgumentParser();p.add_argument('--csv',default='data/hotel_bookings.csv');p.add_argument('--host',default='localhost');p.add_argument('--port',type=int,default=3306);p.add_argument('--user',default='root');p.add_argument('--rebuild',action='store_true');a=p.parse_args()
    if not a.rebuild:raise SystemExit('Pass --rebuild only for the dedicated hotel_analytics project database. Generated project tables will be rebuilt.')
    audit=json.loads(Path('evidence/quality_summary.json').read_text())
    assert hashlib.sha256(Path(a.csv).read_bytes()).hexdigest()==audit['source_sha256'],'Source changed: rerun EDA and review before loading'
    password=getpass.getpass('MySQL password: ')
    url=URL.create('mysql+pymysql',username=a.user,password=password,host=a.host,port=a.port)
    engine=create_engine(url)
    with engine.begin() as con: execute_file(con,'sql/00_schema.sql')
    engine.dispose();engine=create_engine(url.set(database='hotel_analytics'))
    raw=pd.read_csv(a.csv,dtype=str);raw.insert(0,'booking_id',range(1,len(raw)+1));raw=raw.where(raw.notna(),None)
    with engine.begin() as con:
        con.execute(text('DELETE FROM psa_booking'))
        raw.to_sql('psa_booking',con,if_exists='append',index=False,chunksize=1000,method='multi')
    with engine.begin() as con:execute_file(con,'sql/01_transform.sql')
    q="""SELECT COUNT(*) bookings,SUM(is_completed) completed_bookings,SUM(is_failed) failed_arrivals,SUM(is_cancel_only) canceled_only,SUM(is_no_show) no_shows,SUM(eligible_stay) eligible_stays,SUM(eligible_nights) eligible_nights,SUM(estimated_room_revenue) estimated_room_revenue,SUM(cancelled_booked_value) cancelled_booked_value,SUM(repeat_completed) repeat_completed,SUM(is_direct) direct_bookings FROM fact_booking"""
    with engine.connect() as con:
        actual=dict(con.execute(text(q)).mappings().one())
        expected=json.loads(Path('validation_reference/expected_totals.json').read_text())
        for k,v in actual.items():assert abs(float(v)-expected[k])<0.011,(k,v,expected[k])
        Path('evidence/mysql_reconciliation.json').write_text(json.dumps({k:float(v) for k,v in actual.items()},indent=2))
        for table in ['dim_hotel','dim_channel','dim_guest_profile','dim_room','dim_date','fact_booking']:
            pd.read_sql(text('SELECT * FROM '+table),con).to_csv('data/'+table+'.csv',index=False)
    print('Core totals reconcile. Run sql/03_validation.sql in Workbench and record results. CSV warehouse exports are in data/.')
if __name__=='__main__':main()
