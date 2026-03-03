/** @type {import('tailwindcss').Config} */
module.exports = {
  content: [
    './layouts/**/*.html',
    './content/**/*.md',
  ],
  theme: {
    extend: {
      colors: {
        // Backgrounds - Deep, rich cyber theme
        primary: '#050508',      // Deepest background (near black)
        secondary: '#0a0a12',    // Surface backgrounds
        tertiary: '#0f0f1a',     // Card backgrounds
        quaternary: '#141420',   // Border/background elements
        
        // Text - High contrast, readable hierarchy
        'text-primary': '#f5f5f7',   // Primary text (off-white)
        'text-secondary': '#a8a8b0', // Secondary text (light gray)
        'text-muted': '#6b7280',     // Muted text (medium gray)
        'text-dim': '#4b5563',       // Dim text (dark gray)
        
        // Accents - Powerglide Theme (refined Zig orange + cyber palette)
        accent: '#F7A41D',        // Zig orange (primary accent)
        'accent-light': '#ffb84d', // Lighter orange for hover
        'accent-dark': '#d97706',  // Darker orange for gradients
        
        cyan: '#06b6d4',          // Cyber cyan
        'cyan-light': '#22d3ee',  // Lighter cyan
        'cyan-dark': '#0891b2',   // Darker cyan
        
        purple: '#7c3aed',        // Cyber purple
        'purple-light': '#a78bfa', // Lighter purple
        'purple-dark': '#6d28d9',  // Darker purple
        
        // Semantic colors
        success: '#10b981',       // Emerald green
        warning: '#f59e0b',       // Amber
        error: '#ef4444',         // Red
        info: '#3b82f6',          // Blue
      },
      fontFamily: {
        sans: ['Inter', 'system-ui', '-apple-system', 'BlinkMacSystemFont', 'sans-serif'],
        mono: ['JetBrains Mono', 'Fira Code', 'Monaco', 'Consolas', 'monospace'],
      },
      fontSize: {
        'xs': ['0.75rem', { lineHeight: '1.25rem', letterSpacing: '0.01em' }],
        'sm': ['0.875rem', { lineHeight: '1.5rem', letterSpacing: '0.005em' }],
        'base': ['1rem', { lineHeight: '1.75rem', letterSpacing: '0' }],
        'lg': ['1.125rem', { lineHeight: '1.75rem', letterSpacing: '-0.005em' }],
        'xl': ['1.25rem', { lineHeight: '1.75rem', letterSpacing: '-0.01em' }],
        '2xl': ['1.5rem', { lineHeight: '2rem', letterSpacing: '-0.015em' }],
        '3xl': ['1.875rem', { lineHeight: '2.25rem', letterSpacing: '-0.02em' }],
        '4xl': ['2.25rem', { lineHeight: '2.5rem', letterSpacing: '-0.025em' }],
        '5xl': ['3rem', { lineHeight: '1', letterSpacing: '-0.03em' }],
      },
      letterSpacing: {
        'tight': '-0.02em',
        'normal': '0',
        'wide': '0.025em',
        'wider': '0.05em',
      },
      boxShadow: {
        // Refined glow effects with better blur and spread
        'glow-sm': '0 0 10px rgba(247, 164, 29, 0.2)',
        'glow-accent': '0 0 20px rgba(247, 164, 29, 0.3)',
        'glow-accent-lg': '0 0 30px rgba(247, 164, 29, 0.4)',
        'glow-cyan': '0 0 20px rgba(6, 182, 212, 0.25)',
        'glow-cyan-lg': '0 0 30px rgba(6, 182, 212, 0.35)',
        'glow-purple': '0 0 20px rgba(124, 58, 237, 0.25)',
        'glow-purple-lg': '0 0 30px rgba(124, 58, 237, 0.35)',
        
        // Card and UI shadows
        'card': '0 4px 6px -1px rgba(0, 0, 0, 0.3), 0 2px 4px -1px rgba(0, 0, 0, 0.15)',
        'card-lg': '0 10px 15px -3px rgba(0, 0, 0, 0.4), 0 4px 6px -2px rgba(0, 0, 0, 0.2)',
        
        // Neumorphic-style shadows
        'inner-light': 'inset 0 2px 4px 0 rgba(255, 255, 255, 0.05)',
        'inner-dark': 'inset 0 2px 4px 0 rgba(0, 0, 0, 0.3)',
      },
      backgroundImage: {
        // Refined gradients with better color stops
        'gradient-accent': 'linear-gradient(135deg, #F7A41D 0%, #d97706 100%)',
        'gradient-cyan': 'linear-gradient(135deg, #06b6d4 0%, #0891b2 100%)',
        'gradient-purple': 'linear-gradient(135deg, #7c3aed 0%, #6d28d9 100%)',
        'gradient-success': 'linear-gradient(135deg, #10b981 0%, #059669 100%)',
        
        // Subtle background patterns
        'grid-pattern': "linear-gradient(to right, #1a1a25 1px, transparent 1px), linear-gradient(to bottom, #1a1a25 1px, transparent 1px)",
        'dot-pattern': 'radial-gradient(circle, #1a1a25 1px, transparent 1px)',
        
        // Mesh gradients
        'mesh-accent': 'radial-gradient(at 0% 0%, rgba(247, 164, 29, 0.15) 0px, transparent 50%), radial-gradient(at 100% 100%, rgba(6, 182, 212, 0.15) 0px, transparent 50%)',
      },
      backgroundSize: {
        'grid': '50px 50px',
        'dots': '20px 20px',
      },
      animation: {
        'pulse-glow': 'pulse-glow 2s cubic-bezier(0.4, 0, 0.6, 1) infinite',
        'fade-in': 'fade-in 0.3s ease-out',
        'slide-up': 'slide-up 0.3s ease-out',
        'float': 'float 3s ease-in-out infinite',
      },
      keyframes: {
        'pulse-glow': {
          '0%, 100%': { opacity: '1', transform: 'scale(1)' },
          '50%': { opacity: '0.8', transform: 'scale(0.98)' },
        },
        'fade-in': {
          '0%': { opacity: '0' },
          '100%': { opacity: '1' },
        },
        'slide-up': {
          '0%': { transform: 'translateY(10px)', opacity: '0' },
          '100%': { transform: 'translateY(0)', opacity: '1' },
        },
        'float': {
          '0%, 100%': { transform: 'translateY(0)' },
          '50%': { transform: 'translateY(-5px)' },
        },
      },
      transitionDuration: {
        'fast': '150ms',
        'normal': '250ms',
        'slow': '400ms',
      },
      transitionTimingFunction: {
        'ease-out-expo': 'cubic-bezier(0.16, 1, 0.3, 1)',
        'ease-in-expo': 'cubic-bezier(0.7, 0, 0.84, 0)',
      },
    },
  },
  plugins: [],
}
