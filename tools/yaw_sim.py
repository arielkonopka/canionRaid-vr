# Płaski model 4 kół (wątek w chmurze 2026-11-09): stabilność odchylenia auta
# przy pełnym gazie. Odwzorowuje _tire_forces, TCS z wyprzedzeniem i ESP ze
# stunt_car.gd w uproszczeniu. Użycie: python3 tools/yaw_sim.py (lub import run).
import math
def run(P=700e3, v0=240/3.6, T=3.0, tcs="code", rho_t=0.9, peak_ang_r=7.5, peak_ang_f=7.5, wd=0.5,
        mu=1.1*0.94, ls=0.1, kexp=0.0, pert=0.01, power_frac=1.0, esp=False, esp_db=0.06, esp_k=6.0, esp_brake=False, esp_gain=5000.0, esp_bdb=None, verbose=False, lsd=True):
    m=1150.; Iz=1950.; L=2.57; a=L*(1-wd); b=L*wd; t=1.64; h=0.58; r_w=0.33; Iw=1.2+2.0
    Iwf=1.2
    C=1.4; B=math.tan(math.pi/(2*C))
    MF=lambda x: math.sin(C*math.atan(B*x))
    pk=0.11; tf=math.tan(math.radians(peak_ang_f)); tr=math.tan(math.radians(peak_ang_r))
    fz0=m*9.81/4
    pos=[(a,t/2),(a,-t/2),(-b,t/2),(-b,-t/2)]
    u=v0; vl=0.0; r=pert
    om=[u/r_w]*4; kap=[0.0]*4; ta=[0.0]*4
    dFx=0.0; dFy=0.0; tcsf=1.0
    dt=1/120; N=6; hh=dt/N
    tt=0.0; out=[]
    while tt<T:
        # loads
        Fzs=[m*9.81*b/L/2]*2+[m*9.81*a/L/2]*2
        lf=0.58
        loads=[]
        for i,(x,y) in enumerate(pos):
            ax_tr = (-dFx/2 if i<2 else dFx/2)
            share = lf if i<2 else 1-lf
            lat = dFy*share*(1 if y>0 else -1)  # dFy>0 => ay to left => load to right(y<0)... sign below
            loads.append(max(Fzs[i]+ax_tr-lat,0))
        # TCS
        req = P*power_frac*0.88/max((om[2]+om[3])/2,1.0)
        def fmax(i):
            return mu*max(0.5,min(1.3,1-ls*(loads[i]/fz0-1)))*loads[i]
        if tcs=="off":
            target=1.0
        else:
            cap=0.0
            for i in (2,3):
                sy=ta[i]/(tr*(max(loads[i],100)/fz0)**kexp)
                if tcs=="code":
                    tgt=pk*0.9; slip=kap[i]
                    cap+=fmax(i)*r_w*max(0.2,min(1.15,1+2*(tgt-slip)/pk))
                else:
                    # combined: longitudinal target from friction ellipse
                    sxt=math.sqrt(max(rho_t**2-sy*sy,0.0))
                    rho_now=math.hypot(kap[i]/pk,sy)
                    ff=MF(rho_t)*(sxt/rho_t if rho_t>0 else 0)  # long share of force at target
                    cap+=fmax(i)*r_w*ff*max(0.2,min(1.15,1+2*(rho_t-rho_now)))
            target=max(0.05,min(1.0,cap/req))
        if esp:
            rear_a=(abs(ta[2])+abs(ta[3]))/2/tr
            target=min(target, max(0.15,min(1,1-(rear_a-0.5)*1.5)))
            target=min(target, max(0.2,min(1,1-(abs(r)-esp_db)*esp_k)))
        tcsf = target if target<tcsf else min(target, tcsf+25*dt)
        Taxle=req*tcsf
        bT=[0.0]*4
        bdb = esp_db if esp_bdb is None else esp_bdb
        if esp and esp_brake and abs(r)>bdb:
            bT[1 if r>0 else 0]=min((abs(r)-bdb)*esp_gain,1600)
        Fx=[0.0]*4; Fy=[0.0]*4
        for s in range(N):
            lsdT = max(-500,min(500,(om[2]-om[3])*25)) if lsd else 0.0
            for i,(x,y) in enumerate(pos):
                vx=u - r*y; vy=vl + r*x
                vxa=abs(vx)
                slipv=om[i]*r_w - vx
                def relax(st,inp,sig):
                    aa=vxa/sig; tg=inp/vxa
                    return tg+(st-tg)*math.exp(-aa*hh)
                kap[i]=max(-2,min(2,relax(kap[i],slipv,0.25)))
                ta[i]=max(-2,min(2,relax(ta[i],vy,0.45)))
                tp = (tf if i<2 else tr)*(max(loads[i],100)/fz0)**kexp
                sx=kap[i]/pk; sy=ta[i]/tp; rho=math.hypot(sx,sy)
                f=fmax(i)*MF(rho) if rho>1e-9 else 0
                fx=f*sx/rho if rho>1e-9 else 0; fy=-f*sy/rho if rho>1e-9 else 0
                Td = 0.0
                if i>=2: Td = Taxle*0.5 + (-lsdT if i==2 else lsdT)
                troll=-0.013*loads[i]*r_w
                I = Iw if i>=2 else Iwf
                om[i]+= (Td - fx*r_w + troll)/I*hh
                if bT[i]>0 and om[i]>0: om[i]=max(0.0, om[i]-bT[i]/I*hh)
                Fx[i]+=fx/N; Fy[i]+=fy/N
        sFx=sum(Fx)-0.46*u*u; sFy=sum(Fy)
        Mz=sum(pos[i][0]*Fy[i]-pos[i][1]*Fx[i] for i in range(4))
        ax=sFx/m + vl*r; ay=sFy/m - u*r
        u+=ax*dt; vl+=ay*dt; r+=Mz/Iz*dt
        alat = sFy/m
        dFx+=(m*(sFx/m)*h/L-dFx)*min(1,dt/0.08)
        dFy+=(m*alat*h/t - dFy)*min(1,dt/0.1)   # total lateral transfer
        tt+=dt
        if verbose and int(tt*120)%12==0:
            print(f"{tt:4.1f} v={u*3.6:5.1f} r={r:+.3f} beta={math.degrees(math.atan2(vl,u)):+5.1f} ay={alat/9.81:+.2f}g kr={kap[2]:.3f} tcs={tcsf:.2f} rho_r={math.hypot(kap[2]/pk,ta[2]/tr):.2f}")
        if abs(r)>1.0: break
    return tt, r, math.degrees(math.atan2(vl,u)), u*3.6
if __name__=="__main__":
    run(verbose=True)
