module.exports = {
  apps: [
    {
      name: 'excalidraw-server',
      script: 'dist/index.js',
      instances: 1,
      autorestart: true,
      watch: false,
      max_memory_restart: '512M',
      env: {
        NODE_ENV: 'production',
      },
      error_file: '/var/log/excalidraw/error.log',
      out_file: '/var/log/excalidraw/out.log',
      log_date_format: 'YYYY-MM-DD HH:mm:ss',
    },
  ],
};
