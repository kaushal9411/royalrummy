import type { Config } from 'tailwindcss';

const config: Config = {
  content: [
    './src/pages/**/*.{js,ts,jsx,tsx,mdx}',
    './src/components/**/*.{js,ts,jsx,tsx,mdx}',
    './src/app/**/*.{js,ts,jsx,tsx,mdx}',
  ],
  theme: {
    extend: {
      colors: {
        dark: {
          bg:      '#0D1117',
          surface: '#161B22',
          card:    '#21262D',
          border:  '#30363D',
        },
        primary: {
          DEFAULT: '#238636',
          light:   '#2EA043',
        },
        accent:  '#E3B341',
        danger:  '#DA3633',
      },
    },
  },
  plugins: [],
};

export default config;
