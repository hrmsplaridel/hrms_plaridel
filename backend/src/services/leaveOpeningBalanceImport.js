'use strict';
const {applyOpeningBalances}=require('./leaveOpeningBalances');
const COLUMNS=['employee_number','cutoff_date','sick_leave_days','vacation_leave_days','qualifying_leave_days','reason'];
const MAX_ROWS=200,MAX_BYTES=262144;
function fail(message,statusCode=400,extra={}){throw Object.assign(new Error(message),{statusCode,...extra});}
// Strict comma-separated UTF-8 input. Quoted commas, newlines and doubled quotes
// are supported; malformed quotes or a shifted column must never guess balances.
function parseOpeningBalanceCsv(csv){
 if(typeof csv!=='string'||Buffer.byteLength(csv,'utf8')>MAX_BYTES||csv.includes('\0'))fail('Use a UTF-8 CSV file no larger than 256 KB.');
 csv=csv.replace(/^\uFEFF/,'');
 const records=[];let record=[],cell='',quoted=false,closed=false;
 function pushCell(){record.push(cell.trim());cell='';closed=false;}
 function pushRecord(){pushCell();if(record.some(v=>v!==''))records.push(record);record=[];if(records.length>MAX_ROWS+1)fail(`Import at most ${MAX_ROWS} employees at a time.`);}
 for(let i=0;i<csv.length;i++){
  const c=csv[i];
  if(quoted){
   if(c==='"'){if(csv[i+1]==='"'){cell+='"';i++;}else{quoted=false;closed=true;}}
   else cell+=c;
  }else if(c==='"'){
   if(cell!==''||closed)fail('Invalid CSV quoting. Quote the entire field and double embedded quotes.');
   quoted=true;
  }else if(c===',')pushCell();
  else if(c==='\n'||c==='\r'){if(c==='\r'&&csv[i+1]==='\n')i++;pushRecord();}
  else{if(closed)fail('Unexpected text after a quoted CSV field.');cell+=c;}
 }
 if(quoted)fail('A quoted CSV field is not closed.');
 if(cell!==''||record.length||closed)pushRecord();
 if(records.length<2)fail('Include the header and at least one employee row.');
 const headers=records.shift();
 if(headers.length!==COLUMNS.length||new Set(headers).size!==headers.length||COLUMNS.some(k=>!headers.includes(k)))fail(`CSV columns must be: ${COLUMNS.join(',')}.`);
 return records.map((values,i)=>{
  if(values.length!==headers.length)fail(`Row ${i+2} has ${values.length} fields; expected ${headers.length}.`);
  return {...Object.fromEntries(headers.map((key,j)=>[key,values[j]])),row:i+2};
 });
}
async function runOpeningBalanceImport(pool,{actor,csv,commit=false,confirmed=false},options={}){
 if(!actor?.id||!['hr','admin'].includes(actor.role))fail('HR or administrator access is required.',403);
 if(commit&&confirmed!==true)fail('Confirm every imported balance and historical usage has been verified.');
 const rows=parseOpeningBalanceCsv(csv);
 const grouped=new Map();
 for(const row of rows){
  if(!/^\d+$/.test(row.employee_number)||!Number.isSafeInteger(Number(row.employee_number))||Number(row.employee_number)<1||Number(row.employee_number)>2147483647){
   row.error='Enter a valid positive employee number, not a name or biometric ID.';continue;
  }
  const number=String(Number(row.employee_number));row.employee_number=number;
  if(!grouped.has(number))grouped.set(number,[]);grouped.get(number).push(row);
 }
 for(const group of grouped.values())if(group.length>1)for(const row of group)row.error='Duplicate employee number in this file.';
 const client=await pool.connect();let transaction=false;
 try{
  await client.query('BEGIN');transaction=true;
  // Keep the same month-end coordination lock outside preview savepoints.
  await client.query('SELECT pg_advisory_xact_lock(743022, 0)');
  const employees=grouped.size?(await client.query('SELECT id,employee_number,full_name FROM users WHERE employee_number=ANY($1::int[])',[[...grouped.keys()]])).rows:[];
  for(const row of rows){
   if(row.error)continue;
   const matches=employees.filter(e=>String(e.employee_number)===row.employee_number);
   if(matches.length!==1){row.error='Employee number not found or not unique.';continue;}
   row.user_id=matches[0].id;row.employee_name=matches[0].full_name;
   await client.query('SAVEPOINT opening_import_row');
   try{
    await applyOpeningBalances(client,{...row,userId:row.user_id,actor,confirmed:true},options);
   }catch(error){
    if(!error.statusCode)throw error;
    row.error=error.message;
   }finally{
    await client.query('ROLLBACK TO SAVEPOINT opening_import_row');
    await client.query('RELEASE SAVEPOINT opening_import_row');
   }
  }
  const valid=rows.every(row=>!row.error);
  if(commit&&!valid)fail('Import rejected. Fix the listed rows; no balances were saved.',422,{rows});
  if(commit){
   for(const row of [...rows].sort((a,b)=>a.employee_number.localeCompare(b.employee_number))){
    try{await applyOpeningBalances(client,{...row,userId:row.user_id,actor,confirmed:true},options);}
    catch(error){if(!error.statusCode)throw error;row.error=error.message;fail('An employee changed during import. No balances were saved. Validate the file again.',409,{rows});}
   }
   await client.query('COMMIT');
  }else await client.query('ROLLBACK');
  transaction=false;
  return {valid,imported:commit?rows.length:0,total:rows.length,rows};
 }catch(error){if(transaction)await client.query('ROLLBACK');throw error;}
 finally{client.release();}
}
module.exports={COLUMNS,MAX_ROWS,MAX_BYTES,parseOpeningBalanceCsv,runOpeningBalanceImport};
