import { describe, expect, it } from 'vitest';
import { parseRequest } from '../src/lib/passkey-messages';

describe('parseRequest', () => {
  it('reads a request with a token', () => {
    expect(parseRequest('{"kind":"get","token":"abc","challenge":"AQ"}')).toEqual({
      kind: 'get',
      token: 'abc',
      challenge: 'AQ',
    });
  });

  it('drops anything else the page may dispatch', () => {
    for (const detail of [
      'not json',
      'null',
      '"text"',
      '42',
      '{"kind":"get"}',
      '{"token":7}',
      undefined,
      { token: 'x' },
    ]) {
      expect(parseRequest(detail)).toBeNull();
    }
  });
});
