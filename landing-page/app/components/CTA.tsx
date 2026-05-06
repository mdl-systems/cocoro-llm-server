import Link from "next/link";
import { Zap, Star, Shield, Headphones } from "lucide-react";

export default function CTA() {
  return (
    <section className="py-24 relative overflow-hidden">
      {/* Background */}
      <div className="absolute inset-0 bg-gradient-to-br from-slate-950 via-slate-900 to-slate-950"></div>
      <div className="absolute inset-0 bg-[radial-gradient(ellipse_at_center,_var(--tw-gradient-stops))] from-cyan-900/20 via-purple-900/20 to-slate-950"></div>
      
      <div className="container mx-auto px-4 relative z-10">
        <div className="max-w-5xl mx-auto">
          <div className="glass-panel rounded-3xl p-8 md:p-16 bg-gradient-to-br from-slate-900 to-slate-950 border border-slate-800">
            <div className="text-center mb-12">
              <h2 className="text-4xl md:text-5xl font-bold text-white mb-6">
                Ready to <span className="text-transparent bg-clip-text bg-gradient-to-r from-cyan-400 to-purple-400">Dominate</span>?
              </h2>
              <p className="text-xl text-gray-300 max-w-2xl mx-auto">
                The NEXUS-X series is available in multiple configurations. 
                Customize your dream machine or choose from our pre-built expert configurations.
              </p>
            </div>

            <div className="grid md:grid-cols-3 gap-6 mb-12">
              <div className="glass-panel p-6 rounded-2xl text-center hover:bg-cyan-900/20 transition-all cursor-pointer group">
                <div className="mb-4 flex justify-center">
                  <div className="w-16 h-16 rounded-full bg-gradient-to-br from-cyan-500/20 to-blue-600/20 flex items-center justify-center group-hover:scale-110 transition-transform">
                    <Zap className="w-8 h-8 text-cyan-400" />
                  </div>
                </div>
                <h3 className="text-xl font-bold text-white mb-2">Starter Edition</h3>
                <div className="text-3xl font-bold text-cyan-400 mb-2">$4,999</div>
                <ul className="text-left text-gray-400 space-y-2 mb-6 text-sm">
                  <li>✓ RTX 5080</li>
                  <li>✓ i9-14900K</li>
                  <li>✓ 64GB DDR5</li>
                  <li>✓ 2TB NVMe</li>
                </ul>
                <button className="w-full py-3 rounded-xl bg-slate-800 hover:bg-cyan-600 text-white font-semibold transition-all">
                  Configure
                </button>
              </div>

              <div className="glass-panel p-6 rounded-2xl text-center hover:border-cyan-500/50 hover:shadow-2xl hover:shadow-cyan-500/20 transition-all cursor-pointer relative group">
                <div className="absolute top-0 right-0">
                  <div className="bg-gradient-to-r from-cyan-500 to-purple-500 text-white text-xs font-bold px-3 py-1 rounded-bl-xl rounded-tr-2xl">
                    MOST POPULAR
                  </div>
                </div>
                <div className="mb-4 flex justify-center">
                  <div className="w-16 h-16 rounded-full bg-gradient-to-br from-purple-500/20 to-pink-600/20 flex items-center justify-center group-hover:scale-110 transition-transform">
                    <Star className="w-8 h-8 text-purple-400" />
                  </div>
                </div>
                <h3 className="text-xl font-bold text-white mb-2">Pro Master Edition</h3>
                <div className="text-3xl font-bold text-purple-400 mb-2">$7,499</div>
                <ul className="text-left text-gray-400 space-y-2 mb-6 text-sm">
                  <li>✓ RTX 5090</li>
                  <li>✓ i9-14900K OC</li>
                  <li>✓ 128GB DDR5</li>
                  <li>✓ 4TB NVMe</li>
                  <li>✓ Liquid Cooling</li>
                </ul>
                <button className="w-full py-3 rounded-xl bg-gradient-to-r from-cyan-500 to-blue-600 hover:from-cyan-400 hover:to-blue-500 text-white font-semibold shadow-lg shadow-cyan-500/30 transition-all transform hover:scale-105">
                  Build This System
                </button>
              </div>

              <div className="glass-panel p-6 rounded-2xl text-center hover:bg-pink-900/20 transition-all cursor-pointer group">
                <div className="mb-4 flex justify-center">
                  <div className="w-16 h-16 rounded-full bg-gradient-to-br from-pink-500/20 to-red-600/20 flex items-center justify-center group-hover:scale-110 transition-transform">
                    <Headphones className="w-8 h-8 text-pink-400" />
                  </div>
                </div>
                <h3 className="text-xl font-bold text-white mb-2">Ultimate Edition</h3>
                <div className="text-3xl font-bold text-pink-400 mb-2">$12,999</div>
                <ul className="text-left text-gray-400 space-y-2 mb-6 text-sm">
                  <li>✓ Dual RTX 5090 SLI</li>
                  <li>✓ i9-14900K Extreme</li>
                  <li>✓ 256GB DDR5 RGB</li>
                  <li>✓ 8TB NVMe Gen5</li>
                  <li>✓ Custom Liquid Loop</li>
                  <li>✓ Premium Glass Case</li>
                </ul>
                <button className="w-full py-3 rounded-xl bg-slate-800 hover:bg-pink-600 text-white font-semibold transition-all">
                  Contact Sales
                </button>
              </div>
            </div>

            <div className="grid md:grid-cols-3 gap-6 text-center">
              <div className="flex items-center justify-center gap-3 text-gray-400">
                <Shield className="w-6 h-6 text-green-400" />
                <span>2-Year Premium Warranty</span>
              </div>
              <div className="flex items-center justify-center gap-3 text-gray-400">
                <div className="w-6 h-6 rounded-full border-2 border-purple-400 flex items-center justify-center">✓</div>
                <span>Expert Setup & Support</span>
              </div>
              <div className="flex items-center justify-center gap-3 text-gray-400">
                <div className="w-6 h-6 rounded-full border-2 border-cyan-400 flex items-center justify-center">✓</div>
                <span>Free Ship & Installation</span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
