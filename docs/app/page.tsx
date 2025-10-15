import Image from "next/image";

export default function Home() {
  return (
    <div className="min-h-screen flex flex-col bg-[var(--background)]">
      {/* Navbar */}
      <nav className="border-b border-[var(--border-subtle)]/20 bg-[var(--background)]">
        <div className="max-w-5xl mx-auto px-6 py-4 flex items-center justify-between">
          <div className="flex items-center gap-3">
            <Image
              src="/jv.png"
              alt="JV Logo"
              width={40}
              height={40}
              className="rounded"
            />
          </div>
          <a
            href="https://github.com/copydataai/jv"
            target="_blank"
            rel="noopener noreferrer"
            className="flex items-center gap-2 px-4 py-2 rounded-lg border border-[var(--text-secondary)] text-[var(--foreground)] hover:bg-[var(--hover-bg)] transition-colors"
          >
            <svg
              className="w-5 h-5"
              fill="currentColor"
              viewBox="0 0 24 24"
              aria-hidden="true"
            >
              <path
                fillRule="evenodd"
                d="M12 2C6.477 2 2 6.484 2 12.017c0 4.425 2.865 8.18 6.839 9.504.5.092.682-.217.682-.483 0-.237-.008-.868-.013-1.703-2.782.605-3.369-1.343-3.369-1.343-.454-1.158-1.11-1.466-1.11-1.466-.908-.62.069-.608.069-.608 1.003.07 1.531 1.032 1.531 1.032.892 1.53 2.341 1.088 2.91.832.092-.647.35-1.088.636-1.338-2.22-.253-4.555-1.113-4.555-4.951 0-1.093.39-1.988 1.029-2.688-.103-.253-.446-1.272.098-2.65 0 0 .84-.27 2.75 1.026A9.564 9.564 0 0112 6.844c.85.004 1.705.115 2.504.337 1.909-1.296 2.747-1.027 2.747-1.027.546 1.379.202 2.398.1 2.651.64.7 1.028 1.595 1.028 2.688 0 3.848-2.339 4.695-4.566 4.943.359.309.678.92.678 1.855 0 1.338-.012 2.419-.012 2.747 0 .268.18.58.688.482A10.019 10.019 0 0022 12.017C22 6.484 17.522 2 12 2z"
                clipRule="evenodd"
              />
            </svg>
            <span className="font-medium">GitHub</span>
          </a>
        </div>
      </nav>

      {/* Main Content */}
      <main className="flex-1 flex items-center justify-center px-6 py-12">
        <div className="max-w-3xl text-center space-y-4">
          <Image
            src="/jv.png"
            alt="JV Logo"
            width={200}
            height={200}
            className="mx-auto"
          />
          
          <p className="text-xl sm:text-2xl text-[var(--text-secondary)]">
            The simple Java build tool for students and early releases
          </p>

          <div className="grid sm:grid-cols-2 gap-6 mt-12 text-left">
            <div className="p-6 rounded-lg border border-[var(--border)] bg-[var(--card-bg)]">
              <div className="text-3xl mb-3">⚡</div>
              <h3 className="font-semibold text-lg mb-2 text-[var(--foreground)]">Fast Setup</h3>
              <p className="text-[var(--text-secondary)] text-sm">
                Get started in under 1 minute. No complex configuration needed.
              </p>
            </div>

            <div className="p-6 rounded-lg border border-[var(--border)] bg-[var(--card-bg)]">
              <div className="text-3xl mb-3">🎯</div>
              <h3 className="font-semibold text-lg mb-2 text-[var(--foreground)]">Zero Config</h3>
              <p className="text-[var(--text-secondary)] text-sm">
                Convention over configuration. Just write code and run.
              </p>
            </div>

            <div className="p-6 rounded-lg border border-[var(--border)] bg-[var(--card-bg)]">
              <div className="text-3xl mb-3">📦</div>
              <h3 className="font-semibold text-lg mb-2 text-[var(--foreground)]">Simple Dependencies</h3>
              <p className="text-[var(--text-secondary)] text-sm">
                Drop JAR files in the lib/ folder. No XML or DSL required.
              </p>
            </div>

            <div className="p-6 rounded-lg border border-[var(--border)] bg-[var(--card-bg)]">
              <div className="text-3xl mb-3">🧑‍🎓</div>
              <h3 className="font-semibold text-lg mb-2 text-[var(--foreground)]">Student Friendly</h3>
              <p className="text-[var(--text-secondary)] text-sm">
                Perfect for university assignments and learning Java.
              </p>
            </div>
          </div>

          <div className="pt-8">
            <div className="inline-block p-4 rounded-lg bg-[var(--code-bg)] border border-[var(--text-secondary)]">
              <code className="text-sm font-mono text-[var(--code-text)]">
                curl -fsSL https://raw.githubusercontent.com/copydataai/jv/main/install.sh | bash
              </code>
            </div>
          </div>

          <p className="text-sm text-[var(--text-secondary)] pt-4">
            Alternative to Maven, Gradle, and Ant for simple projects
          </p>
        </div>
      </main>

      {/* Footer */}
      <footer className="border-t border-[var(--border-subtle)]/20 py-6 bg-[var(--background)]">
        <div className="max-w-5xl mx-auto px-6 text-center text-sm text-[var(--text-secondary)]">
          <p>MIT License • Built for students and developers</p>
        </div>
      </footer>
    </div>
  );
}
