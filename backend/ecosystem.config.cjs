'use strict';

module.exports = {
  apps: [
    {
      name: 'hrms-backend',
      cwd: __dirname,
      script: 'src/index.js',
      instances: 1,
      exec_mode: 'fork',
      watch: false,
      autorestart: true,

      // A startup failure must not create another once-per-second restart storm.
      // Ten exits before ten seconds of uptime mark the process as errored, with
      // five seconds between attempts so operators can read and react to logs.
      min_uptime: 10000,
      max_restarts: 10,
      restart_delay: 5000,

      kill_timeout: 10000,
      listen_timeout: 10000,
    },
  ],
};
