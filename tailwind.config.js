/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{js,jsx}'],
  theme: {
    extend: {
      colors: {
        brand: {
          50:  '#f0f4ff',
          100: '#dce8ff',
          400: '#6b8cff',
          500: '#4f6ef7',
          600: '#3b57e8',
          700: '#2d44c9',
        },
        surface: {
          50:  '#f8f9fb',
          100: '#f0f2f6',
          200: '#e4e8ef',
          700: '#4b5563',
          900: '#111827',
        },
      },
      fontFamily: {
        sans: ['Inter', 'system-ui', 'sans-serif'],
        mono: ['JetBrains Mono', 'monospace'],
      },
    },
  },
  plugins: [],
}
