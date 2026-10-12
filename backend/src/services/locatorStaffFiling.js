function validateStaffBatch(ids) {
  if (!Array.isArray(ids) || ids.length < 1 || ids.length > 100 ||
      ids.some(id => typeof id !== 'string' || !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(id))) {
    throw Object.assign(new Error('Select between 1 and 100 employees with valid IDs.'), {statusCode:400});
  }
  return [...new Set(ids)];
}
async function runStaffBatch(ids, submit) {
  const results=[];
  for (const employee_id of ids) {
    try {results.push({employee_id,request:await submit(employee_id)});}
    catch(error) {results.push({employee_id,error:error.payload?.error || (error.statusCode ? error.message : 'Unable to file request. Please retry this employee.'),status_code:error.statusCode || 500});}
  }
  return results;
}
module.exports={validateStaffBatch,runStaffBatch};
