import http from 'k6/http';
import { sleep, check } from 'k6';

export const options = {
  thresholds: {
    http_req_failed: ['rate<0.01'],      // <1% errors
    http_req_duration: ['p(95)<800'],    // 95% under 800ms
  },
  scenarios: {
    ramp: {
      executor: 'ramping-arrival-rate',
      startRate: 1,            // reqs/sec
      timeUnit: '1s',
      preAllocatedVUs: 50,
      maxVUs: 200,
      stages: [
        { target: 10, duration: '1m' },
        { target: 25, duration: '2m' },
        { target: 50, duration: '3m' },
        { target: 0,  duration: '30s' }
      ],
    },
  },
};

export default function () {
  const res = http.get('https://YOUR-DOMAIN.com/');
  check(res, { 'status 200': r => r.status === 200 });
  sleep(1);
}
