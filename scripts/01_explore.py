"""Read-only EDA and independent reference outputs. Run from kit root."""
from pathlib import Path
import argparse, hashlib, json
import numpy as np
import pandas as pd

def prepare(raw):
    d=raw.copy(); d.insert(0,'booking_id',range(1,len(d)+1))
    d['arrival_date']=pd.to_datetime(d.arrival_date_year.astype(str)+'-'+d.arrival_date_month+'-'+d.arrival_date_day_of_month.astype(str),format='%Y-%B-%d',errors='coerce')
    d['status_date']=pd.to_datetime(d.reservation_status_date,errors='coerce')
    d['total_nights']=d.stays_in_weekend_nights+d.stays_in_week_nights
    d['departure_date']=d.arrival_date+pd.to_timedelta(d.total_nights,unit='D')
    d['booking_date_estimate']=d.arrival_date-pd.to_timedelta(d.lead_time,unit='D')
    d['country']=d.country.fillna('Unknown')
    d['party_type']=np.select([d.children.isna(),(d.children.fillna(0)+d.babies)>0],['Unknown','With children'],default='Adults only')
    d['lead_band']=pd.cut(d.lead_time,[-1,7,30,90,180,np.inf],labels=['00-07','08-30','031-090','091-180','181+']).astype(str)
    d['is_completed']=d.reservation_status.eq('Check-Out').astype(int)
    d['is_cancel_only']=d.reservation_status.eq('Canceled').astype(int)
    d['is_no_show']=d.reservation_status.eq('No-Show').astype(int)
    d['is_failed']=d.is_cancel_only+d.is_no_show
    d['room_mismatch']=d.reserved_room_type.ne(d.assigned_room_type).astype(int)
    d['is_direct']=d.distribution_channel.eq('Direct').astype(int)
    d['no_known_guests']=((d.adults+d.children.fillna(0)+d.babies)==0).astype(int)
    d['date_mismatch']=((d.is_completed==1)&d.status_date.ne(d.departure_date)).astype(int)
    d['adr_review']=((d.adr<0)|(d.adr>1000)).astype(int)
    d['eligible_stay']=((d.is_completed==1)&(d.total_nights>0)&(d.adr>=0)&(d.no_known_guests==0)&(d.date_mismatch==0)&d.arrival_date.notna()).astype(int)
    d['eligible_nights']=d.total_nights*d.eligible_stay
    d['estimated_room_revenue']=(d.adr*d.eligible_nights).round(2)
    d['cancelled_booked_value']=np.where((d.is_cancel_only==1)&(d.adr>=0)&(d.total_nights>0),d.adr*d.total_nights,0).round(2)
    d['cancel_days_before_arrival']=np.where(d.is_cancel_only.eq(1),(d.arrival_date-d.status_date).dt.days,np.nan)
    d['repeat_completed']=d.is_repeated_guest*d.is_completed
    return d

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--csv',default='data/hotel_bookings.csv');ap.add_argument('--out',default='evidence');a=ap.parse_args()
    src=Path(a.csv);out=Path(a.out);out.mkdir(parents=True,exist_ok=True)
    Path('validation_reference').mkdir(exist_ok=True)
    raw=pd.read_csv(src); d=prepare(raw)
    expected=['hotel','is_canceled','lead_time','arrival_date_year','arrival_date_month','arrival_date_week_number','arrival_date_day_of_month','stays_in_weekend_nights','stays_in_week_nights','adults','children','babies','meal','country','market_segment','distribution_channel','is_repeated_guest','previous_cancellations','previous_bookings_not_canceled','reserved_room_type','assigned_room_type','booking_changes','deposit_type','agent','company','days_in_waiting_list','customer_type','adr','required_car_parking_spaces','total_of_special_requests','reservation_status','reservation_status_date']
    assert set(raw.columns)==set(expected),'Unexpected source columns: review before processing'
    assert d.arrival_date.notna().all() and d.status_date.notna().all(),'Invalid dates require quarantine'
    assert (d.is_failed==d.is_canceled).all(),'Cancellation flag/status mismatch'
    assert raw.reservation_status.isin(['Canceled','Check-Out','No-Show']).all()
    assert (d.total_nights>=0).all() and (d.lead_time>=0).all()
    checks={
      'rows':len(raw),'columns':len(raw.columns),'exact_duplicate_extra_rows':int(raw.duplicated().sum()),
      'zero_night_rows':int(d.total_nights.eq(0).sum()),'zero_adr_rows':int(d.adr.eq(0).sum()),
      'negative_adr_rows':int(d.adr.lt(0).sum()),'adr_above_1000_rows':int(d.adr.gt(1000).sum()),
      'no_known_guests_rows':int(d.no_known_guests.sum()),'checkout_date_mismatch_rows':int(d.date_mismatch.sum()),
      'children_missing_rows':int(raw.children.isna().sum()),'eligible_stays':int(d.eligible_stay.sum()),
      'completed_rows_excluded_from_commercial':int(d.is_completed.sum()-d.eligible_stay.sum()),
      'arrival_min':str(d.arrival_date.min().date()),'arrival_max':str(d.arrival_date.max().date()),
      'source_sha256':hashlib.sha256(src.read_bytes()).hexdigest()}
    totals={ 'bookings':len(d),'completed_bookings':int(d.is_completed.sum()),'failed_arrivals':int(d.is_failed.sum()),
      'canceled_only':int(d.is_cancel_only.sum()),'no_shows':int(d.is_no_show.sum()),'eligible_stays':int(d.eligible_stay.sum()),
      'eligible_nights':int(d.eligible_nights.sum()),'estimated_room_revenue':round(d.estimated_room_revenue.sum(),2),
      'cancelled_booked_value':round(d.cancelled_booked_value.sum(),2),'repeat_completed':int(d.repeat_completed.sum()),
      'direct_bookings':int(d.is_direct.sum()),'median_lead_time':float(d.lead_time.median()) }
    totals.update(weighted_adr=round(totals['estimated_room_revenue']/totals['eligible_nights'],6),
      average_stay=round(totals['eligible_nights']/totals['eligible_stays'],6),
      failed_arrival_rate=round(totals['failed_arrivals']/len(d),8),
      repeat_completed_share=round(totals['repeat_completed']/totals['completed_bookings'],8))
    totals.update(cancellation_rate=round(totals['canceled_only']/len(d),8), no_show_rate=round(totals['no_shows']/len(d),8), direct_booking_share=round(totals['direct_bookings']/len(d),8), revenue_per_eligible_stay=round(totals['estimated_room_revenue']/totals['eligible_stays'],6))
    (out/'quality_summary.json').write_text(json.dumps(checks,indent=2))
    pd.DataFrame(checks.items(),columns=['check','value']).to_csv(out/'quality_summary.csv',index=False)
    (Path('validation_reference')/'expected_totals.json').write_text(json.dumps(totals,indent=2))
    profile=pd.DataFrame({'field':raw.columns,'dtype':raw.dtypes.astype(str).values,'missing':raw.isna().sum().values,'distinct_nonnull':raw.nunique().values})
    profile.to_csv(out/'field_profile.csv',index=False)
    numeric=raw.describe().T
    profile=profile.join(numeric[['min','max','mean']],on='field')
    profile.to_csv(out/'field_profile.csv',index=False)
    pd.crosstab(d.reservation_status,d.is_canceled).to_csv(out/'status_crosscheck.csv')
    audit=d.loc[(d.total_nights==0)|(d.adr_review==1)|(d.no_known_guests==1)|(d.date_mismatch==1)|d.children.isna()].copy()
    audit.to_csv(out/'review_queue.csv',index=False)
    duplicate_sensitivity=[]
    for label,sub in [('retain_all',d),('hypothetical_drop_identical',d.loc[~raw.duplicated()])]:
      duplicate_sensitivity.append({'scenario':label,'rows':len(sub),'failed_rate':sub.is_failed.mean(),'revenue':sub.estimated_room_revenue.sum()})
    pd.DataFrame(duplicate_sensitivity).to_csv(out/'duplicate_sensitivity.csv',index=False)
    print(json.dumps({'quality':checks,'expected':totals},indent=2))
if __name__=='__main__':main()
