import Link from "next/link";
import { ArrowRight, Zap, Cpu, Star, Award, Headphones, Shield } from "lucide-react";
import Hero from "./components/Hero";
import Features from "./components/Features";
import Specifications from "./components/Specifications";
import CTA from "./components/CTA";
import Footer from "./components/Footer";

export default function HomePage() {
  return (
    <div className="min-h-screen bg-slate-950">
      {/* Navigation */}
      <nav className="fixed top-0 left-0 right-0 z-50 glass-panel backdrop-blur-lg border-b border-white/5">
        <div className="container mx-auto px-4">
          <div className="flex items-center justify-between h-20">
            {/* Logo */}
            <Link href="/" className="flex items-center gap-2">
              <div className="w-10 h-10 rounded-xl bg-gradient-to-br from-cyan-500 to-purple-600 flex items-center justify-center">
                <Zap className="w-6 h-6 text-white" />
              </div>
              <span className="text-2xl font-bold text-white tracking-tight">NEXUS<span className="text-cyan-400">X</span></span>
            </Link>

            {/* Desktop Menu */}
            <div className="hidden md:flex items-center gap-8">
              <Link href="#features" className="text-gray-300 hover:text-cyan-400 transition-colors font-medium">Features</Link>
              <Link href="#specs" className="text-gray-300 hover:text-cyan-400 transition-colors font-medium">Specifications</Link>
              <Link href="#product" className="text-gray-300 hover:text-cyan-400 transition-colors font-medium">Configurator</Link>
              <Link href="#testimonials" className="text-gray-300 hover:text-cyan-400 transition-colors font-medium">Reviews</Link>
            </div>

            {/* Actions */}
            <div className="hidden md:flex items-center gap-4">
              <button className="px-6 py-2 rounded-lg text-white hover:bg-white/10 transition-colors">
                Sign In
              </button>
              <button className="px-6 py-2 rounded-lg bg-gradient-to-r from-cyan-500 to-purple-600 text-white font-semibold hover:shadow-lg hover:shadow-cyan-500/30 transition-all">
                Shop Now
              </button>
            </div>

            {/* Mobile Menu Button */}
            <button className="md:hidden p-2 text-white">
              <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 6h16M4 12h16m-7 6h7" />
              </svg>
            </button>
          </div>
        </div>
      </nav>

      {/* Main Content */}
      <main className="pt-20">
        <Hero />
        <Features />
        <Specifications />
        <CTA />
      </main>

      <Footer />
    </div>
  );
}
