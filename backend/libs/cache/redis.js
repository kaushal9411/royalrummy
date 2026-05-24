const { createClient } = require('redis');
const logger = require('../utils/logger');

const client = createClient({
  url: process.env.REDIS_URL,
  socket: {
    tls: process.env.REDIS_TLS === 'true',
    reconnectStrategy: (retries) => {
      if (retries > 20) {
        logger.error('Redis: max reconnect attempts reached');
        return new Error('Max retries exceeded');
      }
      return Math.min(retries * 100, 3000);
    },
  },
});

client.on('connect', () => logger.info('Redis connected'));
client.on('error', (err) => logger.error(`Redis error: ${err.message}`));
client.on('reconnecting', () => logger.warn('Redis reconnecting...'));

(async () => {
  await client.connect();
})();

// Convenience wrappers
module.exports = {
  get: (key) => client.get(key),
  set: (key, value) => client.set(key, value),
  setex: (key, ttl, value) => client.setEx(key, ttl, value),
  del: (key) => client.del(key),
  setnx: async (key, value, ttlSeconds) => {
    const result = await client.set(key, value, {
      NX: true,
      EX: ttlSeconds,
    });
    return result === 'OK';
  },
  incr: (key) => client.incr(key),
  expire: (key, ttl) => client.expire(key, ttl),
  ttl: (key) => client.ttl(key),
  smembers: (key) => client.sMembers(key),
  sadd: (key, ...values) => client.sAdd(key, values),
  spop: (key) => client.sPop(key),
  hset: (key, field, value) => client.hSet(key, field, value),
  hget: (key, field) => client.hGet(key, field),
  hgetall: (key) => client.hGetAll(key),
  lpush: (key, value) => client.lPush(key, value),
  rpop: (key) => client.rPop(key),
  lrange: (key, start, stop) => client.lRange(key, start, stop),
  zadd: (key, score, member) => client.zAdd(key, { score, value: member }),
  zrange: (key, start, stop, withScores) =>
    withScores
      ? client.zRangeWithScores(key, start, stop)
      : client.zRange(key, start, stop),
  zrevrange: (key, start, stop) => client.zRange(key, start, stop, { REV: true }),
  zrank: (key, member) => client.zRank(key, member),
  client,
};
