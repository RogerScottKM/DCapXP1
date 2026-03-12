// ~/dcapx/ecosystem.config.cjs
module.exports = {
  apps: [
    {
      name: 'dcapx-api',
      cwd: '/home/jes/dcapx/apps/api',
      script: 'pnpm',
      args: 'start',
      env: {
        NODE_ENV: 'production',
        PORT: '4010'
      }
    },
    {
      name: 'dcapx-web',
      cwd: '/home/jes/dcapx/apps/web',
      script: 'pnpm',
      args: 'start',
      env: {
        NODE_ENV: 'production',
        PORT: '3000',
        // if your Next proxy uses this, keep it — otherwise harmless
        API_BASE_URL: 'http://127.0.0.1:4010'
      }
    }
  ],
};
