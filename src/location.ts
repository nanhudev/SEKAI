export type Location = { locationId: string; title: string; subtitle: string; optionalRegion?: string; discovered?: boolean };

export class LocationReveal {
  private element: HTMLDivElement;
  private timer = 0;

  constructor(parent: HTMLElement) {
    this.element = document.createElement('div');
    this.element.id = 'location-reveal';
    this.element.setAttribute('aria-live', 'polite');
    parent.append(this.element);
  }

  show(location: Location, quiet = false) {
    window.clearTimeout(this.timer);
    this.element.classList.remove('visible');
    this.element.innerHTML = `<span class="location-region"></span><strong></strong><span class="location-subtitle"></span>`;
    this.element.querySelector<HTMLElement>('.location-region')!.textContent = location.optionalRegion || '';
    this.element.querySelector<HTMLElement>('strong')!.textContent = location.title;
    this.element.querySelector<HTMLElement>('.location-subtitle')!.textContent = location.subtitle;
    requestAnimationFrame(() => this.element.classList.add('visible'));
    this.timer = window.setTimeout(() => this.element.classList.remove('visible'), quiet ? 2600 : 3800);
  }
}
