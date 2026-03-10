/**
 * Slack Thread Router Hook
 * Routes Slack thread replies to corresponding sub-agents
 * Uses correct OpenClaw event name: message_received
 */
const fs = require('fs');
const path = require('path');

const OPENCLAW_HOME = process.env.OPENCLAW_HOME || require('path').join(require('os').homedir(), '.openclaw');
const CONFIG_DIR = require('path').join(OPENCLAW_HOME, 'workspace', 'config');
const THREAD_MAP_FILE = path.join(CONFIG_DIR, 'slack-linear-threads.json');
const ANTON_LOGS_CHANNEL = 'C0AJQ99GW6P';

module.exports = {
  name: 'slack-thread-router',
  version: '2.0.0',

  hooks: {
    message_received: async (context) => {
      try {
        const { message, channel, thread_ts, user } = context;

        if (channel !== ANTON_LOGS_CHANNEL) return;
        if (!thread_ts) return;
        if (context.bot_id) return;

        let threadMap = {};
        try {
          threadMap = JSON.parse(fs.readFileSync(THREAD_MAP_FILE, 'utf8'));
        } catch { return; }

        const taskId = Object.keys(threadMap).find(
          key => threadMap[key] === thread_ts
        );

        if (taskId) {
          console.log(`[slack-thread-router] Message in thread for ${taskId}`);
        }
      } catch (error) {
        console.error(`[slack-thread-router] Error: ${error.message}`);
      }
    }
  }
};
