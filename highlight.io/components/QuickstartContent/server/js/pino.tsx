import { jsGetSnippet } from './shared-snippets-monitoring'
import { QuickStartContent } from '../../QuickstartContent'
import { verifyLogs } from '../shared-snippets-logging'
import { frontendInstallSnippet } from '../shared-snippets-monitoring'

export const JSPinoHTTPJSONLogReorganizedContent: QuickStartContent = {
	title: 'Logging with Pino.JS',
	subtitle: 'Learn how to set up highlight.io log ingestion for Pino.JS.',
	logoKey: 'javascript',
	products: ['Logs'],
	entries: [
		frontendInstallSnippet,
		jsGetSnippet(['node', 'pino']),
		{
			title: 'Setup the Pino HTTP transport.',
			content:
				'The Pino HTTP transport will send JSON logs to highlight.io. ' +
				'Make sure to set the `project` and `service` query string parameters.',
			code: [
				{
					text: `const highlightConfig = {
  projectID: '<YOUR_PROJECT_ID>',
  serviceName: 'my-pino-logger',
  serviceVersion: 'git-sha',
} as NodeOptions


const pinoConfig = {
  level: 'debug',
  transport: {
    target: '@highlight-run/pino',
    options: highlightConfig,
  },
} as LoggerOptions

if (
  typeof process.env.NEXT_RUNTIME === 'undefined' ||
  process.env.NEXT_RUNTIME === 'nodejs'
) {
  const { H } = require('@highlight-run/node')
  H.init(highlightConfig)
}

import type { LoggerOptions } from 'pino'
import pino from 'pino'
import type { NodeOptions } from '@highlight-run/node'

const logger = pino(pinoConfig)


logger.info({ key: 'my-value' }, 'hello, highlight.io!')`,
					language: 'js',
				},
			],
		},
		verifyLogs,
	],
}
