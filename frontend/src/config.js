// Base URL for backend API calls.
//
// - Local dev (`npm start`): .env.development sets REACT_APP_API_BASE_URL to
//   http://localhost:8080 so the frontend on :3000 can reach the backend on
//   :8080 directly.
// - Production build: REACT_APP_API_BASE_URL is left unset, so this resolves
//   to '' (same-origin). In the deployed environment the ALB serves the
//   frontend and backend from the same DNS name and routes /api/* to the
//   backend target group, so relative fetch('/api/...') calls just work
//   without hardcoding any deployed URL at build time.
const API_BASE_URL = process.env.REACT_APP_API_BASE_URL || '';

export default API_BASE_URL;
