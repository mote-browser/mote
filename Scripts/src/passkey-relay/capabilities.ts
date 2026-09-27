/**
 * What this browser can and can't do, for the pages that ask first
 * (`PublicKeyCredential.getClientCapabilities()`): passkeys from the Mac, a
 * phone or a key; under the name field only when a password manager extension
 * offers them (`conditional`); none of the extensions WebKit would have
 * answered for itself except credProps.
 */
export function clientCapabilities(
  native: Record<string, boolean>,
  conditional: boolean,
): Record<string, boolean> {
  const capabilities = Object.assign({}, native);
  Object.keys(capabilities).forEach((key) => {
    if (key.indexOf('extension:') === 0 && key !== 'extension:credProps') capabilities[key] = false;
  });
  return Object.assign(capabilities, {
    conditionalCreate: false,
    conditionalGet: conditional,
    conditionalMediation: conditional,
    relatedOrigins: false,
    signalAllAcceptedCredentials: false,
    signalCurrentUserDetails: false,
    signalUnknownCredential: false,
    hybridTransport: true,
    passkeyPlatformAuthenticator: true,
    userVerifyingPlatformAuthenticator: true,
  });
}
