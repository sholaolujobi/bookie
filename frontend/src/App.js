import React, { useEffect, useState } from 'react';
import API_BASE_URL from './config';

function App() {
  const [state, setState] = useState({ loading: true, error: null, data: null });

  useEffect(() => {
    const controller = new AbortController();

    fetch(`${API_BASE_URL}/api/status`, { signal: controller.signal })
      .then((res) => {
        if (!res.ok) {
          throw new Error(`Backend responded with status ${res.status}`);
        }
        return res.json();
      })
      .then((data) => setState({ loading: false, error: null, data }))
      .catch((err) => {
        if (err.name === 'AbortError') return;
        setState({ loading: false, error: err.message, data: null });
      });

    return () => controller.abort();
  }, []);

  return (
    <main className="app">
      <h1>Bookie</h1>
      {state.loading && <p data-testid="loading">Checking backend…</p>}
      {state.error && (
        <p data-testid="error" className="status-error">
          Failed to reach backend: {state.error}
        </p>
      )}
      {state.data && (
        <div data-testid="result" className="status-success">
          <p className="status-label">{state.data.status}</p>
          <p className="status-guid">{state.data.guid}</p>
        </div>
      )}
    </main>
  );
}

export default App;
