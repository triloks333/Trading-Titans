import React from 'react'
import { LegalPage } from './LegalPage'
import { PRIVACY } from '../lib/legal'

/** Public route: /privacy. This is the URL declared in the Google Play listing,
 *  so it must match the app's policy exactly — content lives in
 *  `src/lib/legal.ts`, ported from `app/lib/core/legal.dart`. */
export const PrivacyPage: React.FC = () => <LegalPage doc={PRIVACY} />
