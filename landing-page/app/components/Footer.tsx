import Link from "next/link";
import { LogIn, Mail, Shield, Zap, Star } from "lucide-react";

export default function Footer() {
  return (
    <footer className="bg-slate-950 border-t border-slate-900 pt-16 pb-8">
      <div className="container mx-auto px-4">
        <div className="grid md:grid-cols-4 gap-12 mb-12">
          {/* Brand */}
          <div className="space-y-4">
            <div className="flex items-center gap-2">
              <div className="w-8 h-8 rounded-lg bg-gradient-to-br from-cyan-500 to-purple-600 flex items-center justify-center">
                <Zap className="w-5 h-5 text-white" />
              </div>
              <span className="text-2xl font-bold text-white tracking-tight">NEXUS<span className="text-cyan-400">X</span></span>
            </div>
            <p className="text-gray-400 text-sm leading-relaxed">
              Redefining high-performance computing with cutting-edge technology and 
              stunning aesthetics. Built for gamers, creators, and professionals.
            </p>
            <div className="flex gap-3">
              <a href="#" className="w-10 h-10 rounded-full bg-slate-800 hover:bg-cyan-500 hover:text-white flex items-center justify-center transition-all">
                <Mail className="w-5 h-5" />
              </a>
              <a href="#" className="w-10 h-10 rounded-full bg-slate-800 hover:bg-pink-600 hover:text-white flex items-center justify-center transition-all">
                <Mail className="w-5 h-5" />
              </a>
              <a href="#" className="w-10 h-10 rounded-full bg-slate-800 hover:bg-blue-400 hover:text-white flex items-center justify-center transition-all">
                <Mail className="w-5 h-5" />
              </a>
              <a href="#" className="w-10 h-10 rounded-full bg-slate-800 hover:bg-gray-400 hover:text-white flex items-center justify-center transition-all">
                <LogIn className="w-5 h-5" />
              </a>
            </div>
          </div>

          {/* Links 1 */}
          <div>
            <h4 className="text-white font-bold text-lg mb-6 flex items-center gap-2">
              <Star className="w-5 h-5 text-purple-400" />
              Products
            </h4>
            <ul className="space-y-3">
              <li><Link href="#" className="text-gray-400 hover:text-cyan-400 transition-colors">Gaming Desktops</Link></li>
              <li><Link href="#" className="text-gray-400 hover:text-cyan-400 transition-colors">Workstation PCs</Link></li>
              <li><Link href="#" className="text-gray-400 hover:text-cyan-400 transition-colors">Mini PCs</Link></li>
              <li><Link href="#" className="text-gray-400 hover:text-cyan-400 transition-colors">Custom Builds</Link></li>
              <li><Link href="#" className="text-gray-400 hover:text-cyan-400 transition-colors">Accessories</Link></li>
            </ul>
          </div>

          {/* Links 2 */}
          <div>
            <h4 className="text-white font-bold text-lg mb-6 flex items-center gap-2">
              <Shield className="w-5 h-5 text-green-400" />
              Support
            </h4>
            <ul className="space-y-3">
              <li><Link href="#" className="text-gray-400 hover:text-cyan-400 transition-colors">Documentation</Link></li>
              <li><Link href="#" className="text-gray-400 hover:text-cyan-400 transition-colors">Drivers & Updates</Link></li>
              <li><Link href="#" className="text-gray-400 hover:text-cyan-400 transition-colors">Warranty Info</Link></li>
              <li><Link href="#" className="text-gray-400 hover:text-cyan-400 transition-colors">Contact Us</Link></li>
              <li><Link href="#" className="text-gray-400 hover:text-cyan-400 transition-colors">Knowledge Base</Link></li>
            </ul>
          </div>

          {/* Newsletter */}
          <div>
            <h4 className="text-white font-bold text-lg mb-6 flex items-center gap-2">
              <Mail className="w-5 h-5 text-pink-400" />
              Stay Updated
            </h4>
            <p className="text-gray-400 text-sm mb-4">
              Get exclusive deals, product updates, and early access to new releases.
            </p>
            <form className="space-y-3">
              <input 
                type="email" 
                placeholder="Enter your email"
                className="w-full px-4 py-3 rounded-xl bg-slate-900 border border-slate-700 text-white placeholder-gray-500 focus:border-cyan-500 focus:outline-none focus:ring-2 focus:ring-cyan-500/30 transition-all"
              />
              <button 
                type="submit"
                className="w-full px-4 py-3 rounded-xl bg-gradient-to-r from-cyan-500 to-purple-600 text-white font-semibold hover:shadow-lg hover:shadow-cyan-500/30 transition-all"
              >
                Subscribe
              </button>
            </form>
          </div>
        </div>

        {/* Bottom */}
        <div className="border-t border-slate-900 pt-8 flex flex-col md:flex-row justify-between items-center gap-4">
          <p className="text-gray-500 text-sm">
            © 2024 NEXUS-X PCSystems. All rights reserved.
          </p>
          <div className="flex gap-6">
            <Link href="#" className="text-gray-500 hover:text-white text-sm transition-colors">Privacy Policy</Link>
            <Link href="#" className="text-gray-500 hover:text-white text-sm transition-colors">Terms of Service</Link>
            <Link href="#" className="text-gray-500 hover:text-white text-sm transition-colors">Cookie Policy</Link>
          </div>
        </div>
      </div>
    </footer>
  );
}
