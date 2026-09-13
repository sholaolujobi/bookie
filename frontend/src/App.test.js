import { render, screen } from '@testing-library/react';
import '@testing-library/jest-dom';
import App from './App';

beforeEach(() => {
  global.fetch = jest.fn(() =>
    Promise.resolve({
      ok: true,
      json: () => Promise.resolve({ status: 'SUCCESS', guid: 'test-guid-1234' }),
    })
  );
});

afterEach(() => {
  jest.resetAllMocks();
});

test('renders SUCCESS and the guid once the backend responds', async () => {
  render(<App />);
  expect(await screen.findByTestId('result')).toBeInTheDocument();
  expect(screen.getByText('SUCCESS')).toBeInTheDocument();
  expect(screen.getByText('test-guid-1234')).toBeInTheDocument();
});

test('shows an error message when the backend call fails', async () => {
  global.fetch.mockImplementationOnce(() => Promise.resolve({ ok: false, status: 500 }));
  render(<App />);
  expect(await screen.findByTestId('error')).toBeInTheDocument();
});
