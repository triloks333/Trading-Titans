import React from 'react'
import { LegalPage } from './LegalPage'
import { TERMS } from '../lib/legal'

/** Public route: /terms. Content lives in `src/lib/legal.ts`, which is kept in
 *  step with the app's `app/lib/core/legal.dart`. */
export const TermsPage: React.FC = () => <LegalPage doc={TERMS} />
