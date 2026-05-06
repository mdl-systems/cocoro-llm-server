import Link from "next/link";
import { ArrowRight, Zap, Microchip, Fan, Activity, Clock, Box } from "lucide-react";

const FeatureCard = ({ 
  icon: Icon, 
  title, 
  description, 
  delay 
}: { 
  icon: React.ElementType; 
  title: string; 
  description: string;
  delay: number;
}) => {
  return (
    <div 
      className="glass-panel rounded-2xl p-6 hover:transform hover:scale-105 transition-all duration-300 hover:neon-border-cyan group"
      style={{ animationDelay: `${delay}ms` }}
    >
      <div className="mb-4 p-3 rounded-xl bg-gradient-to-br from-cyan-500/20 to-blue-600/20 inline-block group-hover:from-cyan-500/30 group-hover:to-blue-600/30 transition-all">
        <Icon className="w-8 h-8 text-cyan-400 group-hover:text-white transition-colors" />
      </div>
      <h3 className="text-xl font-bold text-white mb-2">{title}</h3>
      <p className="text-gray-400 text-sm leading-relaxed">{description}</p>
    </div>
  );
};

const StatCounter = ({ value, label, icon: Icon }: { value: string; label: string; icon: React.ElementType }) => (
  <div className="text-center glass-panel rounded-xl p-6 hover:bg-cyan-900/20 transition-colors">
    <div className="mb-2 text-cyan-400">
      <Icon className="w-12 h-12 mx-auto" />
    </div>
    <div className="text-3xl md:text-4xl font-bold text-white mb-1">{value}</div>
    <div className="text-sm text-cyan-200/70 uppercase tracking-widest">{label}</div>
  </div>
);

export default function Hero() {
  return (
    <section className="relative min-h-screen flex items-center justify-center overflow-hidden">
      {/* Animated Background */}
      <div className="absolute inset-0 bg-[url('data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iNDAiIGhlaWdodD0iNDAiIHhtbG5zPSJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2ZyI+PGRlZnM+PHBhdHRlcm4gaWQ9ImEiIHdpZHRoPSI0MCIgaGVpZ2h0PSI0MCIgcGF0dGVyblVuaXRzPSJ1c2VyU3BhY2VPblVzZSI+PHBhdGggZD0iTTAgNDBMNDAgMFYwTDAgNDB6IiBmaWxsPSJyZ2JhKDAsMjU1LDI1NSwwLjAzKSIvPjwvcGF0dGVybj48L2RlZnM+PHJlY3Qgd2lkdGg9IjEwMCUiIGhlaWdodD0iMTAwJSIgZmlsbD0idXJsKCNhKSIvPjwvc3ZnPg==')] opacity-20"></div>
      
      <div className="absolute inset-0 bg-gradient-to-br from-slate-950 via-purple-950/30 to-slate-950"></div>
      
      {/* Animated Mesh Gradients */}
      <div className="absolute top-0 left-1/4 w-96 h-96 bg-cyan-500/20 rounded-full blur-[100px] animate-pulse-slow"></div>
      <div className="absolute bottom-0 right-1/4 w-96 h-96 bg-purple-500/20 rounded-full blur-[100px] animate-pulse-slow" style={{ animationDelay: '2s' }}></div>
      <div className="absolute top-1/2 left-1/2 transform -translate-x-1/2 -translate-y-1/2 w-[800px] h-[800px] bg-blue-600/10 rounded-full blur-[120px] animate-pulse-slow" style={{ animationDelay: '4s' }}></div>

      <div className="relative z-10 container mx-auto px-4 py-20">
        <div className="grid lg:grid-cols-2 gap-12 items-center">
          {/* Left Content */}
          <div className="space-y-8 animate-fade-in-up" style={{ animationDelay: '0ms' }}>
            <div className="inline-flex items-center gap-2 px-4 py-2 rounded-full bg-gradient-to-r from-cyan-500/20 to-purple-500/20 border border-cyan-500/30 backdrop-blur-sm">
              <span className="relative flex h-2 w-2">
                <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-cyan-400 opacity-75"></span>
                <span className="relative inline-flex rounded-full h-2 w-2 bg-cyan-500"></span>
              </span>
              <span className="text-cyan-400 text-sm font-medium">NEW PRODUCT LAUNCH</span>
            </div>

            <h1 className="text-5xl md:text-7xl lg:text-8xl font-bold text-white leading-tight">
              NEXT-GEN <br/>
              <span className="text-transparent bg-clip-text bg-gradient-to-r from-cyan-400 via-purple-400 to-pink-400 animate-gradient">
                GAMING POWER
              </span>
            </h1>

            <p className="text-lg md:text-xl text-gray-300 max-w-xl leading-relaxed">
              Experience the ultimate fusion of performance and aesthetics. 
              The NEXUS-X series pushes boundaries with next-generation GPU technology 
              and hyper-cooling systems designed for esports domination.
            </p>

            <div className="flex flex-wrap gap-4">
              <Link 
                href="#product"
                className="px-8 py-4 rounded-xl bg-gradient-to-r from-cyan-500 to-blue-600 text-white font-bold text-lg shadow-lg shadow-cyan-500/30 hover:shadow-cyan-500/50 hover:scale-105 transition-all flex items-center gap-2"
              >
                <Zap className="w-5 h-5" />
                Configure Your System
              </Link>
              <Link 
                href="#specs"
                className="px-8 py-4 rounded-xl glass-panel hover:bg-white/5 border border-cyan-500/30 text-white font-semibold text-lg transition-all hover:neon-border-cyan flex items-center gap-2"
              >
                <Activity className="w-5 h-5" />
                View Specifications
              </Link>
            </div>

            <div className="pt-8 grid grid-cols-3 gap-6">
              <StatCounter value="RTX 5090" label="GPU" icon={Microchip} />
              <StatCounter value="9600 MHz" label="Memory" icon={Clock} />
              <StatCounter value="32TB" label="Storage" icon={Box} />
            </div>
          </div>

          {/* Right - 3D Product Visual */}
          <div className="relative animate-slide-in-right" style={{ animationDelay: '400ms' }}>
            {/* Ambient glow behind product */}
            <div className="absolute inset-0 bg-gradient-to-r from-cyan-500/40 to-purple-500/40 blur-[80px] rounded-full"></div>
            
            {/* Product container */}
            <div className="relative w-full aspect-square max-w-lg mx-auto">
              {/* Main chassis */}
              <div className="absolute inset-0 bg-gradient-to-br from-slate-800 to-slate-950 rounded-2xl border border-slate-700 shadow-2xl flex flex-col items-center justify-center overflow-hidden">
                {/* Glass panel */}
                <div className="w-[80%] h-[70%] rounded-xl bg-gradient-to-br from-slate-800/80 to-slate-900/80 backdrop-blur-sm border border-white/10 relative overflow-hidden">
                  {/* RGB Lighting effect */}
                  <div className="absolute inset-0 bg-gradient-to-br from-cyan-500/20 via-purple-500/20 to-pink-500/20 animate-gradient"></div>
                  
                  {/* Internal components visualization */}
                  <div className="absolute inset-4 grid grid-cols-3 grid-rows-2 gap-4">
                    {/* GPU */}
                    <div className="col-span-2 row-span-1 rounded-lg bg-gradient-to-br from-slate-700 to-slate-800 border-2 border-cyan-500/50 flex items-center justify-center overflow-hidden">
                      <div className="w-3/4 h-3/4 rounded bg-gradient-to-br from-slate-800 to-slate-900 flex items-center justify-center relative">
                        <div className="w-2/3 h-2/3 rounded bg-cyan-500/20 absolute animate-pulse"></div>
                        <span className="text-cyan-400 font-mono font-bold text-2xl">GPU</span>
                        <div className="absolute bottom-2 right-2 flex gap-1">
                          <div className="w-1 h-1 rounded-full bg-cyan-400 animate-ping"></div>
                          <div className="w-1 h-1 rounded-full bg-cyan-400 animate-ping" style={{ animationDelay: '0.1s' }}></div>
                          <div className="w-1 h-1 rounded-full bg-cyan-400 animate-ping" style={{ animationDelay: '0.2s' }}></div>
                        </div>
                      </div>
                    </div>
                    
                    {/* CPU */}
                    <div className="row-span-1 rounded-lg bg-gradient-to-br from-slate-700 to-slate-800 border-2 border-purple-500/50 flex items-center justify-center">
                      <div className="text-purple-400 font-mono font-bold text-xl">CPU</div>
                    </div>
                    
                    {/* RAM */}
                    <div className="row-span-1 rounded-lg bg-gradient-to-br from-slate-700 to-slate-800 border-2 border-pink-500/50 flex items-center justify-center">
                      <div className="flex gap-2">
                        <div className="w-8 h-12 bg-pink-500/20 rounded border border-pink-500/50"></div>
                        <div className="w-8 h-12 bg-pink-500/20 rounded border border-pink-500/50"></div>
                        <div className="w-8 h-12 bg-pink-500/20 rounded border border-pink-500/50"></div>
                        <div className="w-8 h-12 bg-pink-500/20 rounded border border-pink-500/50"></div>
                      </div>
                    </div>
                    
                    {/* Storage */}
                    <div className="col-span-2 row-span-1 rounded-lg bg-gradient-to-br from-slate-700 to-slate-800 border-2 border-green-500/50 flex items-center justify-center p-4">
                      <div className="flex gap-4">
                        <div className="w-16 h-24 bg-gradient-to-b from-green-500/20 to-green-600/20 rounded border border-green-500/50 flex items-center justify-center">
                          <span className="text-green-400 text-sm">NVMe</span>
                        </div>
                        <div className="w-16 h-24 bg-gradient-to-b from-green-500/20 to-green-600/20 rounded border border-green-500/50 flex items-center justify-center">
                          <span className="text-green-400 text-sm">NVMe</span>
                        </div>
                      </div>
                    </div>
                  </div>

                  {/* RGB strips */}
                  <div className="absolute top-0 left-0 right-0 h-2 bg-gradient-to-r from-cyan-500 via-purple-500 to-pink-500 animate-gradient"></div>
                  <div className="absolute bottom-0 left-0 right-0 h-2 bg-gradient-to-r from-cyan-500 via-purple-500 to-pink-500 animate-gradient"></div>
                </div>

                {/* Cooling system visualization */}
                <div className="absolute -top-16 left-1/2 transform -translate-x-1/2 flex gap-4">
                  <div className="w-16 h-20 bg-slate-800 rounded-t-xl border border-slate-600 flex items-center justify-center">
                    <Fan className="w-8 h-8 text-cyan-400 animate-spin" style={{ animationDuration: '3s' }} />
                  </div>
                  <div className="w-16 h-20 bg-slate-800 rounded-t-xl border border-slate-600 flex items-center justify-center">
                    <Fan className="w-8 h-8 text-purple-400 animate-spin" style={{ animationDuration: '4s' }} />
                  </div>
                </div>
              </div>

              {/* Floating elements */}
              <div className="absolute -right-8 top-20 w-24 h-24 rounded-xl bg-gradient-to-br from-cyan-500/20 to-blue-500/20 backdrop-blur-md border border-cyan-500/30 flex items-center justify-center animate-float">
                <span className="text-2xl font-bold text-white">5.8</span>
                <span className="text-xs text-cyan-400 ml-1">GHz</span>
              </div>

              <div className="absolute -left-8 bottom-32 w-32 h-32 rounded-xl bg-gradient-to-br from-purple-500/20 to-pink-500/20 backdrop-blur-md border border-purple-500/30 flex items-center justify-center animate-float" style={{ animationDelay: '2s', animationDuration: '8s' }}>
                <div className="flex flex-col items-center">
                  <span className="text-3xl font-bold text-white">32</span>
                  <span className="text-xs text-purple-400">Threads</span>
                </div>
              </div>

              <div className="absolute -right-12 top-48 w-20 h-20 rounded-lg bg-gradient-to-br from-pink-500/20 to-red-500/20 backdrop-blur-md border border-pink-500/30 flex items-center justify-center animate-float" style={{ animationDelay: '1s', animationDuration: '6s' }}>
                <div className="flex flex-col items-center">
                  <span className="text-xl font-bold text-white">48</span>
                  <span className="text-xs text-pink-400">GB</span>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
