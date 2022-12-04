// to run from cli `k6 run deploy/load.k6.js`
import { check } from "k6";
import http from "k6/http";

export function testDepth2(params) {
  // let data = params || { username: 'admin', password: 'test' };
  let reqs = [
    {
      method: "GET",
      url: "http://localhost:8080/depth/2",
      params: {
        headers: {
          // "l5d-dst-override": "app.app.svc.cluster.local",
          Host: "app.app.svc.cluster.local",
        },
      },
    },
  ];
  http.batch(reqs);
}

export default function () {
  testDepth2();
}
