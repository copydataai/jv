# JV Documentation Site

> Documentation for JV - The simple Java build tool for students and early releases

## About JV

JV is a lightweight alternative to Maven, Gradle, and Ant designed for:
- **University assignments** and coursework
- **Simple Java projects** that don't need enterprise complexity
- **Early releases** and prototyping
- **Developers** who prefer CLI simplicity over XML/DSL configuration

### Why JV?

- ⚡ **Fast setup** - Get started in under 1 minute
- 🎯 **Zero configuration** - Convention over configuration
- 📦 **Simple dependencies** - Just drop JARs in `lib/`
- 🧑‍🎓 **Student-friendly** - No steep learning curve

Visit [jv.copydataai.com](https://jv.copydataai.com) for full documentation.

---

## Development Setup

This documentation site is built with [Next.js](https://nextjs.org) and deployed at `jv.copydataai.com`.

### Prerequisites

- Node.js 18+ 
- pnpm (recommended) or npm

### Running Locally

```bash
# Install dependencies
pnpm install

# Start development server
pnpm dev
```

Open [http://localhost:3000](http://localhost:3000) to view the documentation site.

### Project Structure

```
docs/
├── app/              # Next.js app directory
│   ├── page.tsx      # Homepage
│   └── ...           # Documentation pages
├── public/           # Static assets
└── package.json      # Dependencies
```

### Making Changes

1. Edit pages in `app/` directory
2. The site auto-updates as you edit
3. Test locally before deploying

### Deployment

The site is automatically deployed to `jv.copydataai.com` when changes are pushed to the main branch.

For manual deployment:

```bash
# Build for production
pnpm build

# Start production server
pnpm start
```

---

## Contributing

See the main [CONTRIBUTING.md](../CONTRIBUTING.md) in the root directory for contribution guidelines.

## Links

- **Main Repository**: [github.com/copydataai/jv](https://github.com/copydataai/jv)
- **Documentation Site**: [jv.copydataai.com](https://jv.copydataai.com)
- **Examples**: [EXAMPLES.md](../EXAMPLES.md)
- **Changelog**: [CHANGELOG.md](../CHANGELOG.md)
