const { Pool } = require('pg');
const pool = new Pool({ connectionString: 'postgresql://postgres:postgre123@localhost:5433/hrms_plaridel' });

async function insertDevice() {
  await pool.query("INSERT INTO biometric_devices (name, device_id, ip_address, is_active) VALUES ('Main Office ZKTeco', 'device_01', '192.168.1.201', true) ON CONFLICT DO NOTHING");
  console.log('Inserted device successfully!');
  process.exit(0);
}

insertDevice().catch(e => { console.error(e); process.exit(1); });
