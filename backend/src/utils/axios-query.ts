import axios, { AxiosResponse } from 'axios';
import { SocksProxyAgent } from 'socks-proxy-agent';
import backendInfo from '../api/backend-info';
import config from '../config';
import logger from '../logger';
import * as https from 'https';

/** @asyncUnsafe */
export async function query(path: string, throwOnFail: boolean = false, headers?: Record<string, string>): Promise<object | undefined> {
  type axiosOptions = {
    headers: Record<string, string>;
    timeout: number;
    httpsAgent?: https.Agent;
  };

  const setDelay = (secs: number = 1): Promise<void> => new Promise(resolve => setTimeout(() => resolve(), secs * 1000));
  
  const axiosOptions: axiosOptions = {
    headers: {
      'User-Agent': (config.MEMPOOL.USER_AGENT === 'mempool') ? `mempool/v${backendInfo.getBackendInfo().version}` : `${config.MEMPOOL.USER_AGENT}`,
      ...(headers || {})
    },
    timeout: config.SOCKS5PROXY.ENABLED ? 30000 : 20000
  };

  let retry = 0;
  let lastError: any = null;

  // Loglar için URL içerisindeki hassas parametreleri (apikey vb.) maskeleme fonksiyonu
  const sanitizePath = (url: string): string => {
    return url.replace(/([?&])apikey=[^&]+/gi, '$1apikey=REDACTED');
  };

  while (retry < config.MEMPOOL.EXTERNAL_MAX_RETRY) {
    try {
      if (config.SOCKS5PROXY.ENABLED) {
        const socksOptions: any = {
          agentOptions: {
            keepAlive: true,
          },
          hostname: config.SOCKS5PROXY.HOST,
          port: config.SOCKS5PROXY.PORT
        };

        if (config.SOCKS5PROXY.USERNAME && config.SOCKS5PROXY.PASSWORD) {
          socksOptions.username = config.SOCKS5PROXY.USERNAME;
          socksOptions.password = config.SOCKS5PROXY.PASSWORD;
        } else {
          socksOptions.username = `circuit${retry}`;
        }

        axiosOptions.httpsAgent = new SocksProxyAgent(socksOptions);
      }

      const data: AxiosResponse = await axios.get(path, axiosOptions);
      if (data.statusText === 'error' || !data.data) {
        throw new Error(`Could not fetch data from ${sanitizePath(path)}, Error: ${data.status}`);
      }
      return data.data;
    } catch (e) {
      lastError = e;
      // Loglama sırasında açık URL yerine maskelenmiş URL kullanılır
      logger.warn(`Could not connect to ${sanitizePath(path)} (Attempt ${retry + 1}/${config.MEMPOOL.EXTERNAL_MAX_RETRY}). Reason: ` + (e instanceof Error ? e.message : e));
      retry++;
    }
    if (retry < config.MEMPOOL.EXTERNAL_MAX_RETRY) {
      await setDelay(config.MEMPOOL.EXTERNAL_RETRY_INTERVAL);
    }
  }

  logger.err(`Could not connect to ${sanitizePath(path)}. All ${config.MEMPOOL.EXTERNAL_MAX_RETRY} attempts failed`);

  if (throwOnFail && lastError) {
    throw lastError;
  }

  return undefined;
}