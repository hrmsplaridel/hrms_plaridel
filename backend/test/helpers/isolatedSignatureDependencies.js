'use strict';
// These workflow unit tests use tiny SQL fakes. Isolate the new cryptographic
// receipt and confirmation boundary; signature*Security/Integrity/Authorization
// tests and signatureSecurityPostgres.integration exercise the real boundary.
const { randomBytes }=require('node:crypto');
const { withMockedModule }=require('./moduleMocks');
process.env.SIGNATURE_SECURITY_KEYS=JSON.stringify({active:'unit-v1',keys:{'unit-v1':randomBytes(32).toString('base64')}});
const restoreIntegrity=withMockedModule('../../src/services/signatureIntegrity',{
 ...require('../../src/services/signatureIntegrity'),
 recordSignatureEvidence:async()=>({}),protectSignatureRows:async(_db,_context,rows)=>rows,
 assertStoredSignature:async()=>{},assertNativeDocumentSignatures:async()=>{},
});
const restoreAuthorization=withMockedModule('../../src/services/signatureAuthorization',{
 ...require('../../src/services/signatureAuthorization'),requireSigningAuthorization:async()=>({id:'unit-authorization'}),
});
require('node:test').after(()=>{restoreAuthorization();restoreIntegrity();});
