// The page's WebAuthn options, turned into the JSON requests Swift reads in
// `Passkeys.perform`. Each throws (a TypeError) when an option has the wrong
// type, as WebKit's own implementation would.

import type { AssertionRequest, CredentialDescriptor, RegistrationRequest } from '../lib/passkey-messages';
import { encode } from './encoding';

type DescriptorList = ArrayLike<PublicKeyCredentialDescriptor> | null | undefined;

export function descriptors(list: DescriptorList): CredentialDescriptor[] {
  return Array.prototype.map.call(list || [], (credential: PublicKeyCredentialDescriptor) => ({
    id: encode(credential.id),
    transports: Array.prototype.slice.call(credential.transports || []) as string[],
  })) as CredentialDescriptor[];
}

export function assertionRequest(options: PublicKeyCredentialRequestOptions): AssertionRequest {
  return {
    kind: 'get',
    challenge: encode(options.challenge),
    rpId: options.rpId || null,
    allowCredentials: descriptors(options.allowCredentials),
    userVerification: options.userVerification || 'preferred',
  };
}

/** `selection` is the options' `authenticatorSelection`, or an empty one. */
export function registrationRequest(
  options: PublicKeyCredentialCreationOptions,
  selection: AuthenticatorSelectionCriteria,
): RegistrationRequest {
  return {
    kind: 'create',
    challenge: encode(options.challenge),
    rp: { id: (options.rp && options.rp.id) || null },
    user: {
      id: encode(options.user.id),
      name: String(options.user.name),
      displayName: options.user.displayName ? String(options.user.displayName) : '',
    },
    algorithms: Array.prototype.map.call(
      options.pubKeyCredParams || [],
      (parameters: PublicKeyCredentialParameters) => parameters.alg,
    ) as number[],
    excludeCredentials: descriptors(options.excludeCredentials),
    authenticatorAttachment: selection.authenticatorAttachment || null,
    residentKey: selection.residentKey || (selection.requireResidentKey ? 'required' : 'discouraged'),
    userVerification: selection.userVerification || 'preferred',
    attestation: options.attestation || 'none',
  };
}
