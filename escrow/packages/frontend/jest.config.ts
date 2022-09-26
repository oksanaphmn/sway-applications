import type { Config } from '@jest/types';

import baseConfig from '@escrow/test-utils/config';

import pkg from './package.json';

const config: Config.InitialOptions = {
  ...baseConfig,
  rootDir: __dirname,
  displayName: pkg.name,
};

export default config;
