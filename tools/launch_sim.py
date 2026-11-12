# Model 1D ruszania i przyspieszania (wątek w chmurze 2026-11-10): sprzęgło
# ("old" - zamyka się przy 1300 obr. z kół, "pr28" - po zrównaniu obrotów,
# "hyb" - po zrównaniu albo po T_launch s), TCS z wyprzedzeniem (tg = TCS_GAIN),
# pochylnia (grade), napęd rwd/fwd. Uproszczenia: jedna oś napędzana, masa
# przenoszona quasi-statycznie. Użycie: from launch_sim import run.
import math
RPM=60/(2*math.pi)
SHAPE=[[800,0.50],[1500,0.68],[2500,0.83],[3500,0.95],[4500,1.0],[5500,0.97],[6500,0.87],[7200,0.75]]
def interp(c,x):
    if x<=c[0][0]: return c[0][1]
    for i in range(1,len(c)):
        if x<=c[i][0]:
            t=(x-c[i-1][0])/(c[i][0]-c[i-1][0]); return c[i-1][1]+(c[i][1]-c[i-1][1])*t
    return c[-1][1]
def run(kw=180, mode="hyb", layout="rwd", grade=0.0, m=1200.0, T=12.0, tcs=True, T_launch=2.5, verbose=False, tg=0.5, tmin=0.2, tdown=None, ki=None, mu0=1.1*0.94):
    g=9.81; L=2.57; hcg=0.58; r=0.33; Iw=1.2; Ie=0.18
    th=math.atan(grade)
    peak=max(interp(SHAPE,x)*x/RPM for x in range(800,7201,50))
    scale=kw*1000/peak
    curve=[[a,b*scale] for a,b in SHAPE]
    Tpk=max(b for a,b in curve)
    gears=[3.30,2.10,1.55,1.20,0.97,0.80]; fd=3.9
    if kw>350: fd*=math.sqrt(350/kw)
    front_share = 0.6 if layout=="fwd" else 0.5
    dt=1/120; N=6; h=dt/N
    v=0.0; wd=0.0; wn=0.0; kd=0.0; kn=0.0   # driven/non-driven wheel
    rpm=850.0; gear=1; clutch=False; st=0.0; cd=0.0; pend=1; tcsf=1.0
    launching=True; lt=0.0
    dFz=0.0; t=0.0; t100=None; fz0=m*g/4
    pedal=1.0
    corr=1.0
    while t<T:
        cd=max(cd-dt,0)
        if st>0:
            st-=dt
            if st<=0: gear=pend; cd=0.6
            clutch=False
        else:
            ratio=gears[gear-1]*fd
            wheel_rpm=wd*ratio*RPM
            if wheel_rpm<1300:
                clutch=False; launching=True
            elif clutch: pass
            elif mode=="old": clutch=True
            elif mode=="pr28": clutch = wheel_rpm>=rpm-100
            elif mode=="hyb": clutch = wheel_rpm>=rpm-100 or lt>=T_launch
            else:
                clutch = (not launching) or wheel_rpm>=rpm-100
            if clutch: launching=False; lt=0.0
            if wheel_rpm>6700 and gear<6 and cd<=0: pend=gear+1; st=0.18
            elif wheel_rpm<2600 and gear>1 and cd<=0: pend=gear-1; st=0.18
        ratio=gears[gear-1]*fd
        # loads (axle), slope
        Nn=m*g*math.cos(th)
        tr=(m*0+0)  # placeholder
        rear=Nn*(1-front_share) + dFz + m*g*math.sin(th)*hcg/L
        front=Nn - rear
        Fd = (front if layout=="fwd" else rear)/2
        Fn = (rear if layout=="fwd" else front)/2
        def fmax(load): return mu0*max(0.5,min(1.3,1-0.1*(load/fz0-1)))*load
        slipping = (not clutch) and st<=0 and pedal>0.02
        Te=0.0
        if st<=0 and (clutch or slipping):
            Te = interp(curve,rpm)*pedal if rpm<7200 else 0.0
        # TCS feedforward like code
        if tcs and Te>0:
            req=Te*ratio*0.88
            capt=0.0
            if ki is None:
                for _ in range(2):
                    capt+=fmax(Fd)*r*max(tmin,min(1.15,1+tg*(0.099-kd)/0.11))
            else:
                corr=max(0.3,min(1.15,corr+ki*dt*(0.099-kd)/0.11))
                capt=2*fmax(Fd)*r*max(tmin,min(1.15,corr+tg*(0.099-kd)/0.11))
            target=max(0.05,min(1,capt/req))
        else: target=1.0
        tcsf = (target if tdown is None else max(target,tcsf-tdown*dt)) if target<tcsf else min(target,tcsf+25*dt)
        Te*=tcsf
        # engine rpm & clutch torque
        if clutch:
            Tc=Te
        elif slipping:
            if mode=="hyb": lt+=dt
            hold=850+(3800-850)*pedal
            wr=wd*ratio*RPM
            if mode=="new":
                lt+=dt
                base=max(wr,1500.0)
                ref = base + (max(hold,base)-base)*max(0.0,1-lt/T_launch)
                ref = max(ref, wr) if False else ref
            else:
                ref = hold
            new = rpm + max(-9000*dt,min(9000*dt,ref-rpm))
            if mode=="new":
                Tc = Te - Ie*((new-rpm)/RPM)/dt   # inertia release when engine slows
                Tc = max(0.0, min(Tc, 1.6*Tpk))
            else:
                Tc = Te
            rpm=new
        else:
            Tc=0.0
        axle=Tc*ratio*0.88
        refl=Ie*ratio*ratio/2 if clutch else 0.0
        Fx=0.0
        for s in range(N):
            def tire(k,om,load):
                slipv=om*r-v; vxa=abs(v); aa=vxa/0.25
                if aa<1e-3: k=k+slipv/0.25*h
                else:
                    tg=slipv/vxa; k=tg+(k-tg)*math.exp(-aa*h)
                k=max(-2,min(2,k)); sx=k/0.11; rho=abs(sx)
                fm=fmax(load); C=1.4; B=math.tan(math.pi/(2*C))
                f=fm*math.sin(C*math.atan(B*rho))*(1 if sx>=0 else -1)
                low=max(0,min(1,1-vxa/4))
                if low>0: f+=2*load*slipv*low; f=max(-fm,min(fm,f))
                return k,f
            kd,fd_=tire(kd,wd,Fd); kn,fn_=tire(kn,wn,Fn)
            wd+=(axle*0.5-fd_*r-0.013*Fd*r*max(-1,min(1,wd*2)))/(Iw+refl)*h
            wn+=(-fn_*r-0.013*Fn*r*max(-1,min(1,wn*2)))/Iw*h
            Fx+=(2*fd_+2*fn_)/N
        a=(Fx-0.46*v*v-m*g*math.sin(th))/m
        v+=a*dt
        dFz+=(m*a*hcg/L-dFz)*min(1,dt/0.08)
        if clutch: rpm=max(wd*ratio*RPM,850)
        elif st>0: rpm+=max(-9000*dt,min(9000*dt,min(max(wd*gears[pend-1]*fd*RPM,850),7200)-rpm))
        t+=dt
        if t100 is None and v>=100/3.6: t100=t
        if verbose and int(t*120)%12==0 and t<4: print(f"{t:4.1f} v={v*3.6:5.1f} g={gear} rpm={rpm:5.0f} cl={int(clutch)} slip={kd:5.2f} tcs={tcsf:.2f}")
    return t100, v*3.6, kd
